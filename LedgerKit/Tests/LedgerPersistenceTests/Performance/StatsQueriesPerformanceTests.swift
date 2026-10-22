import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Criterion 9 (architecture §15): with 20,000 logged sets across 400 workouts, every `StatsQueries` method
/// answers in under `PerformanceBudget.statsQuery` (50 ms) at the 95th percentile. A timing is only meaningful
/// without other suites competing for the CPU, and seeding takes seconds, so this is `.performance` and
/// `.slow`: nightly lane only (testing-strategy §6). Run it by hand with the `Nightly` plan and
/// `-only-testing:LedgerPersistenceTests/StatsQueriesPerformanceTests`; each query's timings also go into the
/// result bundle.
@Suite(
    "GRDBStatsQueries · timing",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .timeLimit(.minutes(5))
)
struct StatsQueriesPerformanceTests {
    /// Twelve exercises, so each is in about 170 of the 400 workouts: a main lift trained for two years.
    static let exercises = Seeders.catalog(count: 12, version: 1).exercises
    static let now = EventBuilders.start

    /// A file database holding `Seeders.history` of 400 workouts × 50 sets, written through the repository as
    /// the app writes them, with the personal records it detects (product decision #27).
    static func seeded(in directory: TemporaryDirectory) async throws -> DatabaseQueue {
        let queue = try LedgerDatabase.open(at: directory.file("store/ledger.sqlite"))
        let workouts = GRDBWorkoutRepository(queue, now: { now })
        var generator = SeededGenerator(seed: 42)
        let history = Seeders.history(exercises: exercises, workouts: 400, setsPerWorkout: 50, rng: &generator)
        for workout in history {
            try await workouts.materialize(workout, slotUpdates: [])
        }
        return queue
    }

    @Test("Each stats query over 20,000 sets in 400 workouts takes under 50 ms (95th percentile of 20)")
    func everyQuery_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try await Self.seeded(in: directory)
        #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM logged_set") } == 20000)
        let stats = GRDBStatsQueries(queue, now: { Self.now })
        let calendar = try StatsQueriesContract.calendar
        let lift = Self.exercises[0].id
        let week = calendar.week(containing: Self.now)
        let queries: [(name: String, run: @Sendable () async throws -> Void)] = [
            ("lastPerformance", { _ = try await stats.lastPerformance(exerciseID: lift) }),
            ("bestSet", { _ = try await stats.bestSet(exerciseID: lift) }),
            // F12 S1 (N4): the Library's best set of every exercise, in one read.
            ("bestSets", { _ = try await stats.bestSets() }),
            ("bestE1RM", { _ = try await stats.bestE1RM(exerciseID: lift) }),
            ("e1RMByWeek", { _ = try await stats.e1RMByWeek(exerciseID: lift, lastWeeks: 8, calendar: calendar) }),
            ("weeklyVolume", { _ = try await stats.weeklyVolume(in: week) }),
            ("weeklyVolume-allTime", { _ = try await stats.weeklyVolume(in: .distantPast ..< .distantFuture) }),
            ("sessionsCompleted", { _ = try await stats.sessionsCompleted(in: week) }),
            ("sessionCount", { _ = try await stats.sessionCount(exerciseID: lift) }),
            ("personalRecords", { _ = try await stats.personalRecords(exerciseID: lift) }),
            ("recentlyLogged", { _ = try await stats.recentlyLogged(limit: 5) })
        ]
        let clock = ContinuousClock()
        var report: [String] = []
        for query in queries {
            try await query.run() // warm-up: the statement is compiled and the pages are cached
            var timings: [Duration] = []
            for _ in 0 ..< PerformanceBudget.statsRuns {
                try await timings.append(clock.measure { try await query.run() })
            }
            timings.sort()
            let percentile95 = timings[timings.count * 95 / 100 - 1]
            report.append("\(query.name): p95 \(percentile95), median \(timings[timings.count / 2])")
            #expect(percentile95 < PerformanceBudget.statsQuery, "\(query.name): \(timings)")
        }
        Attachment.record(report.joined(separator: "\n"), named: "stats-queries.txt")
    }
}
