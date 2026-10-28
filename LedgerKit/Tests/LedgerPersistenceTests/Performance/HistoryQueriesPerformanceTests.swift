import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S1, N4: the History list's read, `historyEntries()`, over 1,000 workouts in under
/// `PerformanceBudget.historyList` (20 ms) at the 95th percentile, and its observation's fetch too, which runs after
/// every write to the workouts. Nightly lane only, as every timing (testing-strategy §6).
@Suite(
    "GRDBWorkoutRepository · History list timing",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .timeLimit(.minutes(5))
)
struct HistoryQueriesPerformanceTests {
    static let exercises = Seeders.catalog(count: 12, version: 1).exercises
    static let now = EventBuilders.start

    @Test("historyEntries over 1,000 workouts takes under 20 ms (95th percentile of 20), and so does its observation")
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
            let percentile95 = timings[timings.count * 95 / 100 - 1]
            report.append("\(read.name): p95 \(percentile95), median \(timings[timings.count / 2])")
            #expect(percentile95 < PerformanceBudget.historyList, "\(read.name): \(timings)")
        }
        Attachment.record(report.joined(separator: "\n"), named: "history-queries.txt")
    }
}
