#if canImport(HealthKit)
    import HealthKit
#endif
import LedgerDomain

// `HealthAuthorization` (LedgerDomain) as HealthKit reports it. Reading it never asks the lifter: authorization is
// requested at the first "Start workout" (architecture §9). HealthKit reports no read status, by design, so this
// is the sharing status.

public extension HealthAuthorization {
    /// How Debug's Diagnostics screen shows it (F07 criterion 7). Not localised: Diagnostics is Debug-only.
    var diagnosticsLabel: String {
        switch self {
        case .unavailable: "Unavailable"
        case .notDetermined: "Not determined"
        case .denied: "Denied"
        case .authorized: "Authorized"
        }
    }
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
