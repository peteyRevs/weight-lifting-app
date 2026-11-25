#if os(iOS)
    import Foundation
    import HealthKit
    import LedgerDomain

    public extension LiveHealthStore {
        /// The phone's store, over `healthStore` and the mirrored sessions `mirroring` keeps; `onMirrorStart` runs
        /// after each `.mirrorConnected` (see the designated initializer).
        init(
            healthStore: HKHealthStore = HKHealthStore(),
            mirroring: MirroringStartRegistrar<HKWorkoutSession>,
            bundle: Bundle = .main,
            onMirrorStart: @escaping @Sendable (WorkoutID?) async -> Void = { _ in }
        ) {
            self.init(
                provider: PhoneHealthKit(healthStore: healthStore),
                brandName: HealthMetadataKey.brandName(bundle.object(forInfoDictionaryKey:)),
                mirror: mirroring,
                onMirrorStart: onMirrorStart
            )
        }
    }

    /// The phone's HealthKit calls (F16 S3a), kept to the calls themselves: the rules they serve are
    /// `LiveHealthStore`'s, tested over a script. The phone never runs the primary session (ADR-005), so it makes
    /// none, and recovers its mirrored session through `MirroringStartRegistrar`. S3b adds the watch start, the
    /// phone-only save and the record read.
    struct PhoneHealthKit: WorkoutSessionProvider {
        let healthStore: HKHealthStore

        func authorization() -> HealthAuthorization {
            HealthKitAuthorizer(healthStore: healthStore).authorization()
        }

        func requestAuthorization() async throws -> HealthAuthorization {
            try await HealthKitAuthorizer(healthStore: healthStore).requestAuthorization()
        }

        func makeSession() throws -> any WorkoutSessionDriver {
            throw HealthError.unavailable
        }

        func recoverSession() -> (any WorkoutSessionDriver)? {
            nil
        }
    }

    /// A mirrored session's delegate. Sendable without `@unchecked`, as the watch's is: final, and its one
    /// property is a `let` Sendable closure.
    final class MirroredSessionDelegate: NSObject, HKWorkoutSessionDelegate, Sendable {
        private let report: @Sendable (MirroringStartRegistrar<HKWorkoutSession>.Callback) -> Void

        init(report: @escaping @Sendable (MirroringStartRegistrar<HKWorkoutSession>.Callback) -> Void) {
            self.report = report
        }

        func workoutSession(
            _: HKWorkoutSession,
            didChangeTo _: HKWorkoutSessionState,
            from _: HKWorkoutSessionState,
            date _: Date
        ) {}

        func workoutSession(_: HKWorkoutSession, didFailWithError _: any Error) {}

        func workoutSession(_: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError _: (any Error)?) {
            report(.disconnected)
        }

        func workoutSession(_: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
            report(.received(data))
        }
    }
#endif
