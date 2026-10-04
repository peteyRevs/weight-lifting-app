#if os(watchOS)
    import Dependencies
    import HealthKit
    import LedgerDependencies
    import WatchKit

    /// The watch app's delegate (architecture §4): the workout launches HealthKit hands the app, a start from the
    /// phone (`handle(_:)`) and the recovery of a session the system ended (`handleActiveWorkoutRecovery()`). Both
    /// belong to `healthStore`; its protocol has no methods until F16, so for now they only log. The database
    /// opens in `App.init` (`WatchComposition.launch()`), before either arrives.
    public final class WatchAppDelegate: NSObject, WKApplicationDelegate {
        @Dependency(\.healthStore) private var healthStore
        private let logger = LedgerLogger(category: "health")

        public func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
            let activity = workoutConfiguration.activityType.rawValue
            let store = storeName
            logger.log
                .notice("Workout start (activity \(activity, privacy: .public)) left to \(store, privacy: .public)")
        }

        public func handleActiveWorkoutRecovery() {
            let store = storeName
            logger.log.notice("Workout recovery left to \(store, privacy: .public)")
        }

        /// The bound health store's type: an `Unimplemented` stub until F16.
        private var storeName: String {
            String(describing: type(of: healthStore))
        }
    }
#endif
