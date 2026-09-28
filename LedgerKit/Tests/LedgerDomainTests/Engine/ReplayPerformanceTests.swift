import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// The brief's budget: replaying 500 envelopes takes under 5 ms on a simulator. A timing test is only
/// meaningful without other suites competing for the CPU, so it is tagged `.slow` and runs on the
/// nightly lane only (testing-strategy §6). Run it by hand with
/// `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --filter ReplayPerformanceTests`.
@Suite(
    "WorkoutEngine · replay performance",
    .tags(.domain, .slow),
    .enabled(if: ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly", "nightly lane only")
)
struct ReplayPerformanceTests {
    @Test("Replaying 500 shuffled envelopes takes under 5 ms (median of 5)")
    func replay_500Envelopes_under5ms() {
        var random = RandomWorkout(seed: 500)
        let log = random.shuffled(random.log(steps: 499))
        #expect(log.count == 500)
        _ = WorkoutEngine.replay(log)
        let clock = ContinuousClock()
        let timings = (0 ..< 5).map { _ in clock.measure { _ = WorkoutEngine.replay(log) } }.sorted()
        #expect(timings[2] < .milliseconds(5), "median \(timings[2])")
    }
}
