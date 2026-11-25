#if os(watchOS)
    import Dependencies
    import HealthKit
    import LedgerDependencies
    import WatchKit

    /// The watch app's delegate (architecture §4): the workout launches HealthKit hands the app, a start from the
    /// phone (`handle(_:)`) and the recovery of a session the system ended (`handleActiveWorkoutRecovery()`), both
    /// handed to `healthStore` (F16 S3a). The database opens in `App.init` (`WatchComposition.launch()`), which binds
    /// the store, before either arrives.
    public final class WatchAppDelegate: NSObject, WKApplicationDelegate {
        @Dependency(\.healthStore) private var healthStore
        private let logger = LedgerLogger(category: "health")
        /// The recovery `handleActiveWorkoutRecovery()` started: the system's call cannot wait for it.
        private(set) var recovery: Task<Void, Never>?

        /// Reported as `.startRequestedByPhone`; the watch's workout screen starts the session (F18).
        public func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
            let activity = workoutConfiguration.activityType.rawValue
            logger.log.notice("The phone asked for a workout (activity \(activity, privacy: .public))")
            healthStore.noteStartRequestedByPhone()
        }

        public func handleActiveWorkoutRecovery() {
            let store = healthStore
            let recoveryLogger = logger.log
            recovery = Task {
                do {
                    let recovered = try await store.recoverActiveSession()
                    recoveryLogger.notice("Workout recovery found a session: \(recovered, privacy: .public)")
                } catch {
                    recoveryLogger.error("Workout recovery failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
#endif
