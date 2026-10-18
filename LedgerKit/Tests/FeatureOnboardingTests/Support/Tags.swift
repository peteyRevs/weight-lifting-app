import Foundation
import Testing

/// Tags live in the test target (F00 implementation notes #6), as `LedgerDesignTests`' do.
extension Tag {
    /// Every FeatureOnboarding suite of the implementer's (layer tag, testing-strategy §6).
    @Tag static var feature: Self
    /// Suites that compare against committed `__Snapshots__` references.
    @Tag static var snapshot: Self
    /// Longer than 2 s; runs in the nightly lane only (testing-strategy §6).
    @Tag static var slow: Self
}

/// The lane a test plan runs in, from its `LEDGER_TEST_LANE` variable (testing-strategy §6).
nonisolated enum TestLane {
    /// `.slow` tests run only in the nightly plans; the PR plans and `swift test` skip them.
    static var runsSlowTests: Bool {
        ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly"
    }
}
