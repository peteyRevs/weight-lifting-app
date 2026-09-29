import Foundation
import LedgerSnapshotTesting
import Testing

/// Tags live in the test target, not LedgerTestSupport (F00 implementation notes #6).
extension Tag {
    /// Every LedgerDesign suite (layer tag).
    @Tag static var design: Self
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

extension Trait where Self == ConditionTrait {
    /// For a test that needs Dynamic Type or pixel-stable renders, which only the iOS and watchOS
    /// simulators give: `swift test` on the Mac host scales no text size, and its renders can differ
    /// from run to run (F06 review N3).
    nonisolated static var simulatorOnly: Self {
        .disabled(if: SnapshotConfig.platform == "macOS", "needs Dynamic Type and stable renders: iOS or watchOS")
    }
}
