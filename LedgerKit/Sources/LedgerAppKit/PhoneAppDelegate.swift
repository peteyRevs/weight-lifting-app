#if os(iOS)
    import Dependencies
    import HealthKitUI
    import LedgerDependencies
    import UIKit

    /// The iPhone app's delegate (F16 S3a): when the system relaunches the app to take up the watch's mirrored
    /// session after the app ended mid-workout (`shouldHandleActiveWorkoutRecovery`, iOS 26), hands the recovery to
    /// `healthStore`, which `App.init` bound (`AppComposition.launch()`) before any scene connects.
    public final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
        @Dependency(\.healthStore) private var healthStore
        private let logger = LedgerLogger(category: "health")
        /// The recovery `recover()` started: the system's call cannot wait for it.
        private(set) var recovery: Task<Void, Never>?

        public func application(
            _: UIApplication,
            configurationForConnecting session: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            if options.shouldHandleActiveWorkoutRecovery {
                recover()
            }
            return UISceneConfiguration(name: nil, sessionRole: session.role)
        }

        func recover() {
            let store = healthStore
            let recoveryLogger = logger.log
            recovery = Task {
                do {
                    let recovered = try await store.recoverActiveSession()
                    recoveryLogger.notice("Mirrored workout recovery found a session: \(recovered, privacy: .public)")
                } catch {
                    recoveryLogger
                        .error("Mirrored workout recovery failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
#endif
