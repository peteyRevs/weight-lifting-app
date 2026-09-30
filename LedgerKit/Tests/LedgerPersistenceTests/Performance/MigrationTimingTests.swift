import Foundation
@testable import LedgerPersistence
import Testing

/// F05 risk "watchOS first-launch migration": opening and migrating a new database file takes under
/// `PerformanceBudget.firstLaunchOpen` (300 ms). A timing is only meaningful without other suites
/// competing for the CPU, so it is tagged `.performance` and runs in the nightly lane only; the watch
/// figure that matters comes from the `Nightly-Watch` plan (testing-strategy §6). Run it by hand with
/// the `Nightly-Watch` plan and `-only-testing:LedgerPersistenceTests/MigrationTimingTests`.
@Suite(
    "LedgerDatabase · first-launch timing",
    .tags(.persistence, .performance),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only")
)
struct MigrationTimingTests {
    @Test("Creating and migrating a new database file takes under 300 ms (median of 5)")
    func open_newFile_underBudget() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let clock = ContinuousClock()
        let all = try (0 ... PerformanceBudget.runs).map { run in
            let url = directory.file("run-\(run)/ledger.sqlite")
            return try clock.measure { _ = try LedgerDatabase.open(at: url) }
        }
        let timings = all.dropFirst().sorted() // run 0 warms up
        let median = timings[timings.startIndex + timings.count / 2]
        Attachment.record("median \(median); warm-up \(all[0]); runs \(timings)", named: "first-launch-open.txt")
        #expect(median < PerformanceBudget.firstLaunchOpen, "median \(median); warm-up \(all[0]); runs \(timings)")
    }
}
