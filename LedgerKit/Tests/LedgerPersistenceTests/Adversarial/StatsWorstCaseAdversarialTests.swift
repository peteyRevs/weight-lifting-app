import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1, criterion 9: the same 20,000 sets in 400 workouts as the implementer's timing
/// test, in the shape that gives each query the most rows to read. Every set is of one lift, at its own
/// weight (so volume groups 20,000 weights), every workout ended in the current week (so the week's volume
/// and e1RM read them all), and every workout set two records. Nightly lane only, like every timing test.
@Suite(
    "Adversarial S3 · stats timing, worst case",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .timeLimit(.minutes(5))
)
struct StatsWorstCaseAdversarialTests {
    static func seeded(in directory: TemporaryDirectory) async throws -> DatabaseQueue {
        let queue = try LedgerDatabase.open(at: directory.file("store/ledger.sqlite"))
        let workouts = GRDBWorkoutRepository(queue, now: { S3Kit.now })
        for number in 0 ..< 400 {
            let sets = (0 ..< 50).map { S3Kit.set(
                Decimal(4500 + number * 50 + $0) / 100,
                1 + $0 % 12,
                $0 % 7 == 0 ? .added : .working
            ) }
            let ended = S3Kit.now.addingTimeInterval(Double(number - 399) * 60)
            let workout = S3Kit.workout(number, endedAt: ended, minutes: 1, [S3Kit.RowSpec(S3Kit.bench, sets)])
            let records = [
                S3Kit.record(S3Kit.bench, .estimatedOneRepMax(sets[11].weight), in: workout),
                S3Kit.record(S3Kit.bench, .weightAtReps(sets[49].weight, Reps(clamping: 2)), in: workout)
            ]
            try await workouts.materialize(
                workout,
                summary: WorkoutEngine.summary(workout, prs: records),
                prs: records,
                slotUpdates: []
            )
        }
        return queue
    }

    @Test("Each stats query over 20,000 sets of one lift in one week takes under 50 ms (95th percentile of 20)")
    func everyQuery_underBudget_inTheWorstShape() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try await Self.seeded(in: directory)
        let stats = GRDBStatsQueries(queue, now: { S3Kit.now })
        let calendar = S3Kit.calendar()
        let week = calendar.week(containing: S3Kit.now)
        #expect(try await stats.sessionsCompleted(in: week) == 400)
        let queries: [(name: String, run: @Sendable () async throws -> Void)] = [
            ("lastPerformance", { _ = try await stats.lastPerformance(exerciseID: S3Kit.bench) }),
            ("bestSet", { _ = try await stats.bestSet(exerciseID: S3Kit.bench) }),
            ("bestE1RM", { _ = try await stats.bestE1RM(exerciseID: S3Kit.bench) }),
            (
                "e1RMByWeek",
                { _ = try await stats.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: 8, calendar: calendar) }
            ),
            ("weeklyVolume", { _ = try await stats.weeklyVolume(in: week) }),
            ("sessionsCompleted", { _ = try await stats.sessionsCompleted(in: week) }),
            ("sessionCount", { _ = try await stats.sessionCount(exerciseID: S3Kit.bench) }),
            ("personalRecords", { _ = try await stats.personalRecords(exerciseID: S3Kit.bench) }),
            ("recentlyLogged", { _ = try await stats.recentlyLogged(limit: 5) })
        ]
        let clock = ContinuousClock()
        var report: [String] = []
        for query in queries {
            try await query.run() // warm-up
            var timings: [Duration] = []
            for _ in 0 ..< PerformanceBudget.statsRuns {
                try await timings.append(clock.measure { try await query.run() })
            }
            timings.sort()
            let percentile95 = timings[timings.count * 95 / 100 - 1]
            report.append("\(query.name): p95 \(percentile95), median \(timings[timings.count / 2])")
            #expect(percentile95 < PerformanceBudget.statsQuery, "\(query.name): \(timings)")
        }
        Attachment.record(report.joined(separator: "\n"), named: "stats-queries-worst-case.txt")
    }
}
