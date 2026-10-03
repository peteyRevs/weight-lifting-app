import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Product decision #27's worst case: a typo fixed in the first of 400 workouts of one lift, 20,000 sets, every
/// workout after the first setting both records. The edit replays all 400 workouts (`RecordReplay`), and each
/// run changes 399 records: the 2,250 lb single takes every later estimate record away, and the fix gives them
/// back. Like criterion 9's stats queries, the edit, and the bests query F10 calls before each workout, must
/// take under `PerformanceBudget.statsQuery` (50 ms) at the 95th percentile, and a new workout of the lift,
/// which replays only itself, too. Nightly lane only, like every timing test; each timing goes into the result
/// bundle.
@Suite(
    "GRDBWorkoutRepository · record replay timing",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .timeLimit(.minutes(5))
)
struct RecordReplayPerformanceTests {
    static let lift = WorkoutRepositoryContract.exercises[0]
    static let now = EventBuilders.start

    /// Workout `number` of the lift: set *j* is 2.5 × (`number` + *j* + 1) lb for 1 + *j* % 12 reps, so each
    /// workout is one step heavier at every rep count than the one before. Workouts start an hour apart.
    static func workout(_ number: Int) -> WorkoutState {
        let sets = (0 ..< 50).map { Seeders.SetSpec(Decimal(number + $0 + 1) * 2.5, 1 + $0 % 12) }
        let end = now.addingTimeInterval(3600 * Double(number - 399))
        return Seeders.workout(number: number, endedAt: end, minutes: 30, [Seeders.ExerciseLog(lift, sets)])
    }

    static func seeded(in directory: TemporaryDirectory) async throws -> DatabaseQueue {
        let queue = try LedgerDatabase.open(at: directory.file("store/ledger.sqlite"))
        let workouts = GRDBWorkoutRepository(queue, now: { now })
        for number in 0 ..< 400 {
            try await workouts.materialize(workout(number), slotUpdates: [])
        }
        return queue
    }

    @Test("Fixing a typo in the first of 400 workouts of one lift, 20,000 sets, takes under 50 ms (95th percentile)")
    func typoInTheFirstWorkout_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try await Self.seeded(in: directory)
        let workouts = GRDBWorkoutRepository(queue, now: { Self.now })
        let stats = GRDBStatsQueries(queue, now: { Self.now })
        #expect(try await stats.personalRecords(exerciseID: Self.lift.id).count == 399 * 2)
        let first = Self.workout(0).exercises[0]
        var typo = first.sets
        typo[0].weight = .pounds(2250)
        let next = Self.workout(400)
        let queries: [(name: String, run: @Sendable () async throws -> Void)] = [
            ("bests(before:for:) the newest", { _ = try await stats.bests(before: next, for: [Self.lift.id]) }),
            ("materialize a new workout", { try await workouts.materialize(next, slotUpdates: []) })
        ]
        let clock = ContinuousClock()
        var report: [String] = []
        var timings: [Duration] = []
        for run in 0 ... PerformanceBudget.statsRuns { // the first run is the warm-up
            // While the typo stands no later estimate beats 2,250 lb; every later workout keeps its weight record.
            let typoStands = run.isMultiple(of: 2)
            try await timings.append(clock.measure {
                try await workouts.updateSets(workoutExerciseID: first.id, sets: typoStands ? typo : first.sets)
            })
            let records = try await stats.personalRecords(exerciseID: Self.lift.id).count
            #expect(records == (typoStands ? 399 : 399 * 2), "run \(run)")
        }
        timings.removeFirst()
        report.append(Self.line("updateSets of the first workout", timings))
        #expect(Self.percentile95(timings) < PerformanceBudget.statsQuery, "updateSets: \(timings)")
        for query in queries {
            try await query.run() // warm-up
            var runs: [Duration] = []
            for _ in 0 ..< PerformanceBudget.statsRuns {
                try await runs.append(clock.measure { try await query.run() })
            }
            report.append(Self.line(query.name, runs))
            #expect(Self.percentile95(runs) < PerformanceBudget.statsQuery, "\(query.name): \(runs)")
        }
        Attachment.record(report.joined(separator: "\n"), named: "record-replay.txt")
    }

    static func percentile95(_ timings: [Duration]) -> Duration {
        timings.sorted()[timings.count * 95 / 100 - 1]
    }

    static func line(_ name: String, _ timings: [Duration]) -> String {
        "\(name): p95 \(percentile95(timings)), median \(timings.sorted()[timings.count / 2])"
    }
}
