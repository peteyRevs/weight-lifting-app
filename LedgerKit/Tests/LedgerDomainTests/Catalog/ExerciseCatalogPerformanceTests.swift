import Foundation
@testable import LedgerDomain
import Testing

/// The brief's budget: decoding the catalog takes under 20 ms on iPhone. A timing test is only
/// meaningful without other suites competing for the CPU, so it is tagged `.slow` and runs on the
/// nightly lane only (testing-strategy §6), like `ReplayPerformanceTests`. Run it by hand with
/// `LEDGER_TEST_LANE=nightly swift test --package-path LedgerKit --filter ExerciseCatalogPerformanceTests`.
@Suite(
    "ExerciseCatalog · decode performance",
    .tags(.domain, .slow),
    .enabled(if: ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly", "nightly lane only")
)
struct ExerciseCatalogPerformanceTests {
    @Test("seed() takes under 20 ms (median of 5)")
    func seed_under20ms() throws {
        _ = try ExerciseCatalog.seed()
        let clock = ContinuousClock()
        let timings = try (0 ..< 5).map { _ in try clock.measure { _ = try ExerciseCatalog.seed() } }.sorted()
        #expect(timings[2] < .milliseconds(20), "median \(timings[2])")
    }
}
