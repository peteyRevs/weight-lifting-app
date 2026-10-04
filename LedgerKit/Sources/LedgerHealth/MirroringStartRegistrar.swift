#if os(iOS)
    import HealthKit
#endif
import os
import Synchronization

/// The phone's end of HealthKit mirroring (ADR-005): assigns `workoutSessionMirroringStartHandler` and keeps
/// every session the watch starts mirroring, which HealthKit does not retain for the app. F16 and F17 extend it
/// to hand each session to the live workout transport and start the Live Activity. The app uses it on iOS as
/// `MirroringStartRegistrar<HKWorkoutSession>(healthStore:)`; tests give it their own session type and handler
/// slot, so they touch no HealthKit (testing-strategy §3).
///
/// HealthKit calls the handler on an arbitrary background queue, and the handler cannot wait, so the sessions
/// sit behind a `Mutex` (not an actor, which the handler could only reach through an unstructured `Task`, after
/// it had returned): engineering-standards §4's exception for state a framework callback writes synchronously.
public final class MirroringStartRegistrar<Session: AnyObject & Sendable>: Sendable {
    /// Installs the handler where the sessions come from (`HKHealthStore`'s property, in the app).
    private let install: @Sendable (@escaping @Sendable (Session) -> Void) -> Void
    private let sessions = Mutex<[Session]>([])
    private let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "health")

    init(install: @escaping @Sendable (@escaping @Sendable (Session) -> Void) -> Void) {
        self.install = install
    }

    /// Assigns the handler. Call it synchronously at the top of launch, before any `await` (ADR-005; F07
    /// criterion 6): a launch that the watch's mirroring started delivers the session to it at once.
    public func register() {
        install { [weak self] session in
            self?.keep(session)
        }
    }

    /// Every session handed to the handler so far, oldest first.
    public var mirroredSessions: [Session] {
        sessions.withLock { $0 }
    }

    func keep(_ session: Session) {
        let count = sessions.withLock { kept in
            kept.append(session)
            return kept.count
        }
        logger.notice("Kept a mirrored workout session (\(count, privacy: .public) so far)")
    }
}

#if os(iOS)
    public extension MirroringStartRegistrar where Session == HKWorkoutSession {
        /// The app's registrar, over `healthStore`'s `workoutSessionMirroringStartHandler`.
        convenience init(healthStore: HKHealthStore = HKHealthStore()) {
            self.init { handler in
                healthStore.workoutSessionMirroringStartHandler = handler
            }
        }
    }
#endif
