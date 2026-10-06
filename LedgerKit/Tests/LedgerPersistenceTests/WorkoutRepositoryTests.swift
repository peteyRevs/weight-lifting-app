import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBWorkoutRepository`: criterion 3 (materialisation in one transaction, with e1RMs, personal records and
/// misses), the shared contract, and how a second materialisation and `updateSets` diff a workout's rows.
@Suite("GRDBWorkoutRepository", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutRepositoryTests {
    typealias Contract = WorkoutRepositoryContract

    /// The live rows of each table, in order: workout, exercise, set, personal record, miss.
    static let liveCounts = """
    SELECT (SELECT COUNT(*) FROM workout WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM workout_exercise WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM logged_set WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM personal_record WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM slot_miss WHERE deleted_at IS NULL)
    """

    /// Every row of the four history tables and `slot_miss`, with its stamps.
    static let everyRow = """
    SELECT 'workout' || id || updated_at || quote(deleted_at) FROM workout
    UNION ALL SELECT 'exercise' || id || updated_at || quote(deleted_at) FROM workout_exercise
    UNION ALL SELECT 'set' || id || updated_at || quote(deleted_at) FROM logged_set
    UNION ALL SELECT 'record' || id || updated_at || quote(deleted_at) FROM personal_record
    UNION ALL SELECT 'miss' || id || updated_at || quote(deleted_at) FROM slot_miss
    ORDER BY 1
    """

    /// The contract workout of two days before `workout`, its first exercise at 180 lb where `workout` has 185:
    /// its other exercises tie, so `workout` sets two records over it and no other.
    static func earlier(than workout: WorkoutState) -> WorkoutState {
        var earlier = Contract.workout(number: 1, endedAt: workout.startedAt.addingTimeInterval(-2 * 86400))
        for index in earlier.exercises[0].sets.indices {
            earlier.exercises[0].sets[index].weight = .pounds(180)
        }
        return earlier
    }

    /// The two personal records `workout` sets over `earlier(than:)` (product decision #27): a best estimate
    /// and a best weight at 5 reps, achieved at its start.
    static func records(of workout: WorkoutState) -> [PersonalRecord] {
        let exercise = workout.exercises[0].exerciseID
        func record(_ kind: PRKind, over previous: PRKind) -> PersonalRecord {
            PersonalRecord(
                exerciseID: exercise,
                kind: kind,
                previous: previous,
                achievedAt: workout.startedAt,
                workoutID: workout.id
            )
        }
        let five = Reps(clamping: 5)
        return [
            record(
                .estimatedOneRepMax(Weight(grams: 94404)), // 185 lb × 36 / 32, to the gram
                over: .estimatedOneRepMax(OneRepMax.brzycki(weight: .pounds(180), reps: five) ?? .zero)
            ),
            record(.weightAtReps(.pounds(185), five), over: .weightAtReps(.pounds(180), five))
        ]
    }

    /// The contract program and `earlier(than:)` the contract workout stored in a database, the contract
    /// workout, the records it sets, and a slot of the program whose misses the workout changed.
    struct Scenario {
        let repositories: Repositories
        let earlier: WorkoutState
        let workout: WorkoutState
        let records: [PersonalRecord]
        let slots: [Slot]

        init() async throws {
            repositories = try await Repositories.withProgramExercises()
            let program = try ProgramRepositoryContract.program()
            try await repositories.programs.save(program)
            workout = Contract.workout()
            earlier = WorkoutRepositoryTests.earlier(than: workout)
            try await repositories.history.materialize(earlier)
            repositories.clock.advance()
            var slot = program.days[0].slots[0]
            slot.misses = [2]
            slots = [slot]
            records = WorkoutRepositoryTests.records(of: workout)
        }

        /// Materialises the workout with its slot.
        func materialize() async throws {
            try await repositories.history.materialize(workout, slotUpdates: slots)
        }
    }

    @Test("The GRDB repository keeps the contract clause", arguments: WorkoutRepositoryContract.clauses)
    func contract_clauseHolds(_ clause: WorkoutRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Repositories.withProgramExercises().history)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("The GRDB repository keeps the storage clause", arguments: WorkoutRepositoryContract.storageClauses)
    func storageClause_holds(_ clause: WorkoutRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Repositories.withProgramExercises().history)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("The GRDB repository keeps the linked clause", arguments: WorkoutRepositoryContract.linkedClauses)
    func linkedClause_holds(_ clause: WorkoutRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Repositories.withProgramExercises().history)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("Criterion 3: five exercises materialise as workout, exercise, set, record and miss rows, in one transaction")
    func materialize_writesEveryTable_inOneTransaction() async throws {
        let scenario = try await Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        let transactions = try await repositories.statements(startingWith: "") {
            try await scenario.materialize()
        }.filter { $0.hasPrefix("BEGIN") || $0.hasPrefix("COMMIT") }
        #expect(transactions == ["BEGIN IMMEDIATE TRANSACTION", "COMMIT TRANSACTION"])
        #expect(workout.exercises.count == 5)
        let bench = workout.exercises[0].exerciseID
        // The earlier workout and this one, 16 misses of the program, and the one the workout recorded.
        #expect(try await repositories.texts(Self.liveCounts) == ["2 10 38 2 17"])
        #expect(try await repositories.workouts.workout(id: workout.id) == workout)
        #expect(try await repositories.stats.personalRecords(exerciseID: bench) == scenario.records)
        #expect(try await repositories.programs.active()?.days[0].slots[0].misses == [2])
    }

    @Test("Every done set of at most 12 reps stores its Brzycki e1RM, whatever its kind; other sets store NULL")
    func materialize_computesE1RM() async throws {
        let scenario = try await Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        try await repositories.history.materialize(workout)
        let stored = try await repositories.texts("""
        SELECT logged_set.kind || ' ' || logged_set.reps || ' ' || quote(logged_set.e1rm_e7g)
        FROM logged_set JOIN workout_exercise ON workout_exercise.id = logged_set.workout_exercise_id
        WHERE workout_id = ?
        ORDER BY workout_exercise.position, logged_set.position
        """, [ColumnCodec.text(workout.id)])
        func estimate(_ weight: Weight, _ reps: Int) throws -> String {
            let e1RM = try #require(OneRepMax.brzycki(weight: weight, reps: Reps(clamping: reps)))
            return try String(e1RM.e7g())
        }
        let bench = try "working 5 " + estimate(.pounds(185), 5)
        let incline = try "working 10 " + estimate(.pounds(55), 10)
        let row = try "working 8 " + estimate(.pounds(70), 8)
        let pulldown = try "working 12 " + estimate(.pounds(100), 12)
        #expect(bench == "working 5 944040000000") // 185 lb × 36 / 32 = 94,403.91… g, to the gram
        #expect(try stored == [
            bench, bench, bench, bench, bench,
            incline, incline, "working 9 " + estimate(.pounds(55), 9), "drop 10 " + estimate(.pounds(45), 10),
            row, row, row, "working 8 NULL", // the last is not done
            pulldown, pulldown, "added 13 NULL", // above 12 reps
            "working 15 NULL", "working 15 NULL", "warmup 5 " + estimate(.pounds(20), 5)
        ])
    }

    @Test("Criterion 3: a failure part-way through leaves no rows, and the program's misses as they were")
    func failedMaterialize_leavesNoRows() async throws {
        let scenario = try await Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        let before = try await repositories.texts(Self.everyRow)
        // The workout, its five exercises and its sets are written before the first record's insert fails.
        try await repositories.execute("""
        CREATE TRIGGER injected BEFORE INSERT ON personal_record
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END
        """)
        await #expect(throws: DatabaseError.self) {
            try await scenario.materialize()
        }
        #expect(try await repositories.texts(Self.everyRow) == before)
        // An undone set adds nothing to the volume, so its inexact weight (an eighth of a pound) is refused only
        // at its own row, the last set of the last exercise.
        try await repositories.execute("DROP TRIGGER injected")
        var inexact = workout
        let eighth = Weight.pounds(Decimal(string: "100.125") ?? 0)
        inexact.exercises[4].sets[2].weight = eighth
        inexact.exercises[4].sets[2].doneAt = nil
        await #expect(throws: LedgerPersistenceError.inexactWeight(eighth.grams)) {
            try await repositories.history.materialize(inexact)
        }
        #expect(try await repositories.texts(Self.everyRow) == before)
        #expect(try await repositories.texts(Self.liveCounts) == ["1 5 19 0 16"])
    }
}

/// The columns a materialisation writes, and the dates it refuses.
extension WorkoutRepositoryTests {
    @Test("A workout row holds exact totals, REAL dates and its source; an exercise row its targets")
    func materialize_writesTheDocumentedColumns() async throws {
        let scenario = try await Scenario()
        let repositories = scenario.repositories
        var workout = scenario.workout
        workout.source = WorkoutSource(
            programID: ProgramID(EventBuilders.uuid(0x71)),
            weekIndex: 2,
            dayTemplateID: DayTemplateID(EventBuilders.uuid(0x72))
        )
        try await repositories.history.materialize(workout)
        let root = """
        SELECT week_index || ' ' || tag || ' ' || is_deload || ' ' || typeof(started_at) || ' ' || started_at
            || ' ' || ended_at || ' ' || phase || ' ' || units || ' ' || volume_e7g_reps || ' ' || done_sets
            || ' ' || total_sets || ' ' || pr_count FROM workout WHERE id = ?
        """
        let volume = try workout.volume.e7gReps()
        #expect(try await repositories.texts(root, [ColumnCodec.text(workout.id)]) == [
            "2 W0 0 real 811225200.0 811228800.0 finished lb \(volume) 18 19 2"
        ])
        let exercise = """
        SELECT position || ' ' || equipment || ' ' || step_e7g || ' ' || rest_seconds || ' ' || rpe_x2 || ' '
            || is_superset_with_previous || ' ' || target_sets || ' ' || target_reps || ' ' || target_load_e7g
            || ' ' || quote(slot_id) FROM workout_exercise WHERE position = 0 AND workout_id = ?
        """
        #expect(try await repositories.texts(exercise, [ColumnCodec.text(workout.id)]) == [
            "0 barbell 22679618500 90 16 0 5 5 839145884500 '00000000-0000-0000-0000-000000005107'"
        ])
        let record = """
        SELECT kind || ' ' || weight_e7g || ' ' || quote(reps) || ' ' || quote(previous_kind) || ' '
            || quote(previous_weight_e7g) || ' ' || quote(previous_reps) || ' ' || achieved_at
        FROM personal_record ORDER BY kind
        """
        // Achieved at the workout's start; the previous best is the earlier workout's 180 × 5 (918520000000 is
        // 180 lb × 36 / 32 = 91,852.46 g, to the gram).
        #expect(try await repositories.texts(record) == [
            "estimatedOneRepMax 944040000000 NULL 'estimatedOneRepMax' 918520000000 NULL 811225200.0",
            "weightAtReps 839145884500 5 'weightAtReps' 816466266000 5 811225200.0"
        ])
    }

    @Test("A date that is not finite is refused by name, in the workout or a set; nothing is stored")
    func nonFiniteDates_areRefused() async throws {
        let scenario = try await Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        let never = Date(timeIntervalSinceReferenceDate: .infinity)
        var started = workout
        started.startedAt = Date(timeIntervalSinceReferenceDate: -.infinity)
        var ended = workout
        ended.endedAt = never
        var ticked = workout
        ticked.exercises[2].sets[0].doneAt = Date(timeIntervalSinceReferenceDate: .nan)
        for refused in [started, ended, ticked] {
            await #expect(throws: LedgerPersistenceError.nonFiniteDate) {
                try await repositories.history.materialize(refused)
            }
        }
        #expect(try await repositories.texts(Self.liveCounts) == ["1 5 19 0 16"])
    }
}
