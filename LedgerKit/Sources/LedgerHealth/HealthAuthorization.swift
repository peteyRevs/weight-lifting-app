#if canImport(HealthKit)
    import HealthKit
#endif

/// What HealthKit reports about Ledger saving workouts, for Debug's Diagnostics screen (F07 criterion 7). Reading it
/// never asks the lifter: authorization is requested at the first "Start workout" (architecture §9). HealthKit
/// reports no read status, by design, so this is the sharing status.
public enum HealthAuthorization: String, Sendable {
    case unavailable = "Unavailable"
    case notDetermined = "Not determined"
    case denied = "Denied"
    case authorized = "Authorized"
}

#if canImport(HealthKit)
    public extension HealthAuthorization {
        init(_ status: HKAuthorizationStatus) {
            switch status {
            case .sharingAuthorized: self = .authorized
            case .sharingDenied: self = .denied
            default: self = .notDetermined
            }
        }

        /// What this device's HealthKit reports for workouts now. The defaults read HealthKit itself, which needs the
        /// app's HealthKit entitlement: a package test passes its own.
        static func workouts(
            isAvailable: Bool = HKHealthStore.isHealthDataAvailable(),
            status: () -> HKAuthorizationStatus = { HKHealthStore().authorizationStatus(for: .workoutType()) }
        ) -> HealthAuthorization {
            isAvailable ? HealthAuthorization(status()) : .unavailable
        }
    }
#endif
