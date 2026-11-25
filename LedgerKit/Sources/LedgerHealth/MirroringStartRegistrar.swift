import Foundation
#if os(iOS)
    import HealthKit
#endif
import LedgerDomain
import os
import Synchronization

/// The phone's end of HealthKit mirroring (ADR-005): assigns `workoutSessionMirroringStartHandler`, keeps every
/// session the watch starts mirroring (HealthKit does not retain them for the app, and may hand over several per
/// workout, R1 §2.3), observes each through its own delegate, and drops one only when it disconnects. Sends go to
/// the newest. Its `mirrorEvents` feed the phone's `LiveHealthStore`. The app uses it on iOS as
/// `MirroringStartRegistrar<HKWorkoutSession>(healthStore:)`; tests give it their own session type, handler slot
/// and delegate, so they touch no HealthKit (testing-strategy §3).
///
/// HealthKit calls the handler on an arbitrary background queue, and the handler cannot wait, so the sessions
/// sit behind a `Mutex` (not an actor, which the handler could only reach through an unstructured `Task`, after
/// it had returned): engineering-standards §4's exception for state a framework callback writes synchronously.
public final class MirroringStartRegistrar<Session: AnyObject & Sendable>: MirrorReceiver, Sendable {
    /// What a kept session's delegate reports.
    enum Callback: Equatable, Sendable {
        case disconnected, received([Data])
    }

    /// Attaches a delegate to a session that reports through the closure, and returns what must be kept alive
    /// for it (HealthKit holds its delegate weakly).
    typealias Observe = @Sendable (Session, @escaping @Sendable (Callback) -> Void) -> any Sendable

    /// Installs the handler where the sessions come from (`HKHealthStore`'s property, in the app).
    private let install: @Sendable (@escaping @Sendable (Session) -> Void) -> Void
    private let observe: Observe
    private let sendData: @Sendable (Session, Data) async throws -> Void
    private let recoverSession: @Sendable () async throws -> Session?
    private let sessions = Mutex<[(session: Session, delegate: any Sendable)]>([])
    private let sink: AsyncStream<MirrorEvent>.Continuation
    private let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "health")
    let mirrorEvents: AsyncStream<MirrorEvent>

    init(
        install: @escaping @Sendable (@escaping @Sendable (Session) -> Void) -> Void,
        observe: @escaping Observe = { _, _ in () },
        send: @escaping @Sendable (Session, Data) async throws -> Void = { _, _ in },
        recover: @escaping @Sendable () async throws -> Session? = { nil }
    ) {
        self.install = install
        self.observe = observe
        sendData = send
        recoverSession = recover
        (mirrorEvents, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Assigns the handler. Call it synchronously at the top of launch, before any `await` (ADR-005; F07
    /// criterion 6): a launch that the watch's mirroring started delivers the session to it at once.
    public func register() {
        install { [weak self] session in
            self?.keep(session)
        }
    }

    /// Every session handed to the handler and not yet disconnected, oldest first.
    public var mirroredSessions: [Session] {
        sessions.withLock { $0.map(\.session) }
    }

    func keep(_ session: Session) {
        let delegate = observe(session) { [weak self, weak session] callback in
            guard let self, let session else {
                return
            }
            handle(callback, from: session)
        }
        let count = sessions.withLock { kept in
            kept.append((session, delegate))
            return kept.count
        }
        logger.notice("Kept a mirrored workout session (\(count, privacy: .public) so far)")
        sink.yield(.connected)
    }

    func send(_ data: Data) async throws {
        guard let newest = sessions.withLock({ $0.last?.session }) else {
            throw HealthError.noActiveSession
        }
        try await sendData(newest, data)
    }

    func recover() async throws -> Bool {
        guard let session = try await recoverSession() else {
            return false
        }
        keep(session)
        return true
    }

    private func handle(_ callback: Callback, from session: Session) {
        switch callback {
        case .disconnected:
            sessions.withLock { kept in kept.removeAll { $0.session === session } }
            logger.notice("A mirrored workout session disconnected")
            sink.yield(.disconnected)
        case let .received(batch):
            sink.yield(.received(batch))
        }
    }
}

#if os(iOS)
    public extension MirroringStartRegistrar where Session == HKWorkoutSession {
        /// The app's registrar, over `healthStore`'s `workoutSessionMirroringStartHandler`.
        convenience init(healthStore: HKHealthStore = HKHealthStore()) {
            self.init(
                install: { healthStore.workoutSessionMirroringStartHandler = $0 },
                observe: { session, report in
                    let delegate = MirroredSessionDelegate(report: report)
                    session.delegate = delegate
                    return delegate
                },
                send: { session, data in
                    try await healthKitCall { try await session.sendToRemoteWorkoutSession(data: data) }
                },
                recover: { try await healthKitCall { try await healthStore.recoverActiveWorkoutSession() } }
            )
        }
    }
#endif
