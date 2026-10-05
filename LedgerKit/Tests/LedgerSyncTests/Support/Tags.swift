import Foundation
import Testing

/// The tags live in the test target, not LedgerTestSupport, as in `LedgerDomainTests` (F02 notes): tags there
/// would pull swift-testing into every target that links it.
extension Tag {
    /// Every LedgerSync suite (layer tag, testing-strategy §6).
    @Tag static var sync: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
    /// Timing tests against a budget of architecture §15; nightly lane only (testing-strategy §6).
    @Tag static var performance: Self
    /// Tests that take more than about two seconds; nightly lane only (testing-strategy §6).
    @Tag static var slow: Self
}

/// The lane a test plan runs in, from its `LEDGER_TEST_LANE` variable (testing-strategy §6), as
/// `LedgerPersistenceTests` reads it.
enum TestLane {
    /// True in the nightly plans only: there a seeded matrix runs every seed of the lane on every set-up, and
    /// the timing tests run. The PR plans and `swift test` run the cut each such matrix names.
    static var isNightly: Bool {
        ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly"
    }
}
