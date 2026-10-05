import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Product decision #27's replay, timed in the implementer's shape: 400 workouts of one lift, 20,000 sets, every
/// workout after the first setting both records. Nightly lane only, like every timing test; each timing goes into
/// the result bundle. Three budgets (architecture §15):
/// - a typo fixed in the first workout: the replay walks all 400 workouts and 399 records change each run (the
///   2,250 lb single takes every later estimate record away, the fix gives them back), a History write
///   (`PerformanceBudget.historyWrite`);
/// - the bests F10 asks for before a new workout, a query (`statsQuery`);
/// - recording new workouts at the end of history, each replaying only itself (`recordNewWorkout`), and the
///   same with what a finish adds since F10 S3: program updates, misses and the log dropped.
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

    @Test("A typo fixed in the first of 400 workouts, the bests before a new one, and new ones: each within budget")
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
        let clock = ContinuousClock()
        var edits: [Duration] = []
        for run in 0 ... PerformanceBudget.statsRuns { // the first run is the warm-up
            // While the typo stands no later estimate beats 2,250 lb; every later workout keeps its weight record.
            let typoStands = run.isMultiple(of: 2)
            try await edits.append(clock.measure {
                try await workouts.updateSets(workoutExerciseID: first.id, sets: typoStands ? typo : first.sets)
            })
            let records = try await stats.personalRecords(exerciseID: Self.lift.id).count
            #expect(records == (typoStands ? 399 : 399 * 2), "run \(run)")
        }
        // The last run left the typo in place: put the first workout back, untimed.
        try await workouts.updateSets(workoutExerciseID: first.id, sets: first.sets)
        let next = Self.workout(400)
        var bests: [Duration] = []
        var additions: [Duration] = []
        for run in 0 ... PerformanceBudget.statsRuns { // the first run of each is the warm-up
            try await bests.append(clock.measure { _ = try await stats.bests(before: next, for: [Self.lift.id]) })
            let new = Self.workout(400 + run) // a new workout, at the end of history
            try await additions.append(clock.measure { try await workouts.materialize(new, slotUpdates: []) })
        }
        #expect(try await stats.personalRecords(exerciseID: Self.lift.id).count == 420 * 2)
        let timed = [
            ("updateSets of the first workout", edits, PerformanceBudget.historyWrite),
            ("bests(before:for:) the newest", bests, PerformanceBudget.statsQuery),
            ("materialize a new workout at the end", additions, PerformanceBudget.recordNewWorkout)
        ]
        for (name, timings, budget) in timed {
            let runs = Array(timings.dropFirst())
            #expect(Self.percentile95(runs) < budget, "\(name): \(runs)")
        }
        let report = timed.map { Self.line($0.0, Array($0.1.dropFirst())) }.joined(separator: "\n")
        Attachment.record(report, named: "record-replay.txt")
    }

    /// F10 S3 criterion 8: the finish path as the host now runs it. Each run stores a new workout at the end of
    /// history with a swap that changes two slots of its program, the misses of a day's five slots, and its
    /// log of sixty events dropped, in the one transaction.
    @Test("A finish at the end of 400 workouts, with its program updates, misses and log, is within budget")
    func finishWithProgramUpdatesAndTheLog_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try await Self.seeded(in: directory)
        let workouts = GRDBWorkoutRepository(queue, now: { Self.now })
        let events = GRDBWorkoutEventStore(queue, now: { Self.now })
        try await GRDBExerciseRepository(queue, now: { Self.now })
            .seedIfNeeded(ProgramRepositoryContract.exercises, version: 1)
        let program = try ProgramRepositoryContract.program()
        try await GRDBProgramRepository(queue, now: { Self.now }).save(program)
        let clock = ContinuousClock()
        var saves: [Duration] = []
        for run in 0 ... PerformanceBudget.statsRuns { // the first run is the warm-up
            var new = Self.workout(400 + run)
            new.source = WorkoutSource(programID: program.id, weekIndex: 1, dayTemplateID: program.days[0].id)
            // Each run swaps the two slots to another exercise than the run before, and moves every miss.
            let exercise = ProgramRepositoryContract.exercises[1 + run % 2].id
            new.programUpdates = [program.days[0].slots[0].id: exercise, program.days[0].slots[2].id: exercise]
            let slots = program.days[0].slots.map { slot in
                var missed = slot
                missed.misses = [run % 7]
                return missed
            }
            let log = Array(repeating: WorkoutEvent.restSkipped, count: 60)
            _ = try await events.append(EventBuilders.log(from: log, workoutID: new.id))
            let saved = new
            try await saves.append(clock.measure {
                _ = try await workouts.materialize(saved, slotUpdates: slots, droppingLog: true)
            })
        }
        #expect(try await events.uncompactedWorkoutIDs().isEmpty)
        #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workout") } == 421)
        let runs = Array(saves.dropFirst())
        #expect(Self.percentile95(runs) < PerformanceBudget.recordNewWorkout, "the finish save: \(runs)")
        let name = "materialize a new workout at the end, with 2 program updates, 5 misses and a log of 60 dropped"
        Attachment.record(Self.line(name, runs), named: "finish-save.txt")
    }

    static func percentile95(_ timings: [Duration]) -> Duration {
        timings.sorted()[timings.count * 95 / 100 - 1]
    }

    static func line(_ name: String, _ timings: [Duration]) -> String {
        "\(name): p95 \(percentile95(timings)), median \(timings.sorted()[timings.count / 2])"
    }
}
