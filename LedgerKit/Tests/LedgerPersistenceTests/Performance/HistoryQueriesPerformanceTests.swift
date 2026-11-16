import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S1, N4: the History list's read, `historyEntries()`, over 1,000 workouts in under
/// `PerformanceBudget.historyList` (20 ms) at the 95th percentile, and its observation's fetch too, which runs after
/// every write to the workouts; on the runner, the median under the budget times the factor (`PerformanceRunner`).
/// Nightly lane only, as every timing (testing-strategy §6).
///
/// Issue #118: the watch leg of run 43857732010 failed at a median of 60.6 ms against 60 (20 ms times 3), while
/// both reads took 12.9 ms here on the iPhone 17 simulator and 14.4 ms on the Series 12 (46mm) watch simulator.
/// About 80 % of that was finding columns by name in the rows `Row.fetchAll` copies, which lowercases every column
/// name on each lookup; the read now decodes each row from a cursor (`fetchHistoryEntries`): 4.7 ms on the iPhone,
/// 4.9 ms on the watch (medians of 20). At the failed run's ~4.2 times this Mac's watch, about 21 ms of the 60.
@Suite(
    "GRDBWorkoutRepository · History list timing",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .timeLimit(.minutes(5))
)
struct HistoryQueriesPerformanceTests {
    static let exercises = Seeders.catalog(count: 12, version: 1).exercises
    static let now = EventBuilders.start

    @Test("historyEntries over 1,000 workouts, and its observation, under 20 ms (p95 of 20; on the runner, the median)")
    func historyEntries_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try LedgerDatabase.open(at: directory.file("store/ledger.sqlite"))
        let workouts = GRDBWorkoutRepository(queue, now: { Self.now })
        var generator = SeededGenerator(seed: 42)
        let history = Seeders.history(exercises: Self.exercises, workouts: 1000, setsPerWorkout: 5, rng: &generator)
        for workout in history {
            try await workouts.materialize(workout, slotUpdates: [])
        }
        #expect(try await workouts.historyEntries().count == 1000)
        let reads: [(name: String, run: @Sendable () async throws -> Void)] = [
            ("historyEntries", { _ = try await workouts.historyEntries() }),
            ("observeHistoryEntries' fetch", {
                _ = try await queue.read { try GRDBWorkoutRepository.fetchHistoryEntries(in: $0) }
            })
        ]
        let clock = ContinuousClock()
        var report: [String] = []
        for read in reads {
            try await read.run() // warm-up: the statement is compiled and the pages are cached
            var timings: [Duration] = []
            for _ in 0 ..< PerformanceBudget.statsRuns {
                try await timings.append(clock.measure { try await read.run() })
            }
            timings.sort()
            let verdict = PerformanceRunner.verdict(timings, budget: PerformanceBudget.historyList)
            report.append("\(read.name): p95 \(verdict.percentile95), median \(verdict.median)")
            #expect(verdict.isWithinBudget, "\(read.name): \(verdict)")
        }
        Attachment.record(report.joined(separator: "\n"), named: "history-queries.txt")
    }
}
