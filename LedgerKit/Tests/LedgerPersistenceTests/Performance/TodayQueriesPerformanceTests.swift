import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F09 S5, criterion 12 (architecture §15): on the 20,000-set database of `StatsQueriesPerformanceTests`,
/// with the bundled catalog and the spec's seed program stored as the app stores them, each read Today makes
/// answers in under `PerformanceBudget.statsQuery` (50 ms) at the 95th percentile. The four it observes are
/// timed as the fetch each observation runs; the two it reads itself, as it reads them: the workouts of the
/// longest stretch it asks for (a stats week and a program week that share one day, 13 days) and the volume
/// of the week before. `.performance` and `.slow`: nightly lane only, as that suite is, and run by hand the
/// same way.
@Suite(
    "Today's reads · timing",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .timeLimit(.minutes(5))
)
struct TodayQueriesPerformanceTests {
    @Test("Each of Today's six reads over 20,000 sets takes under 50 ms (95th percentile of 20)")
    func everyRead_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try await StatsQueriesPerformanceTests.seeded(in: directory)
        let now = StatsQueriesPerformanceTests.now
        let exercises = GRDBExerciseRepository(queue, now: { now })
        let programs = GRDBProgramRepository(queue, now: { now })
        let settings = GRDBSettingsRepository(queue, now: { now })
        let workouts = GRDBWorkoutRepository(queue, now: { now })
        let stats = GRDBStatsQueries(queue, now: { now })
        try await exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        try await programs.save(Fixtures.seedProgram())
        #expect(try await exercises.all().count >= 200)
        #expect(try await programs.active() != nil)

        let calendar = try StatsQueriesContract.calendar
        let week = calendar.week(containing: now)
        let thirteenDays = week.lowerBound.addingTimeInterval(-6 * 86400) ..< week.upperBound
        #expect(try await !workouts.workouts(in: thirteenDays).isEmpty, "the stretch holds workouts to read")
        let previousWeek = calendar.previousCompleteWeek(before: now)
        let reads: [(name: String, run: @Sendable () async throws -> Void)] = [
            ("activeProgram", { _ = try await programs.active() }),
            ("settings", { _ = try await settings.load() }),
            ("exercises", { _ = try await exercises.all() }),
            ("recentWorkouts", { _ = try await workouts.recent(limit: 5) }),
            ("weekWorkouts", { _ = try await workouts.workouts(in: thirteenDays) }),
            ("previousWeekVolume", { _ = try await stats.weeklyVolume(in: previousWeek) })
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
            #expect(percentile95 < PerformanceBudget.statsQuery, "\(read.name): \(timings)")
        }
        Attachment.record(report.joined(separator: "\n"), named: "today-reads.txt")
    }
}
