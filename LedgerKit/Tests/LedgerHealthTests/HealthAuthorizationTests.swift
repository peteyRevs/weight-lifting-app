#if canImport(HealthKit)
    import HealthKit
    @testable import LedgerHealth
    import Testing

    /// `HealthAuthorization`, which Debug's Diagnostics screen shows (F07 criterion 7). The tests pass HealthKit's
    /// answers in: a package test host has no HealthKit entitlement (testing-strategy §3).
    @Suite("Health authorization")
    struct HealthAuthorizationTests {
        @Test("Each sharing status reads as itself")
        func statuses_map() {
            #expect(HealthAuthorization(.notDetermined) == .notDetermined)
            #expect(HealthAuthorization(.sharingDenied) == .denied)
            #expect(HealthAuthorization(.sharingAuthorized) == .authorized)
        }

        @Test("Where HealthKit is unavailable, nothing is asked of it")
        func unavailable_asksNothing() {
            var asked = false
            let result = HealthAuthorization.workouts(isAvailable: false) {
                asked = true
                return .sharingAuthorized
            }
            #expect(result == .unavailable)
            #expect(!asked)
        }

        @Test("Where HealthKit is available, its status for workouts is reported")
        func available_reportsTheStatus() {
            #expect(HealthAuthorization.workouts(isAvailable: true) { .sharingDenied } == .denied)
        }
    }
#endif
