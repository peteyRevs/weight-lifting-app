import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Product decision #27 in the GRDB repository (`RecordReplay`): what the contracts cannot see through the
/// protocols. Each workout's `pr_count`, the record rows a write touches, the scope a write re-checks (the
/// exercises it touched, from the earliest place the workout held), one result and one statement order for one
/// history, and the strict read of the history it replays.
@Suite("GRDBWorkoutRepository · records detected again", .tags(.persistence), .timeLimit(.minutes(1)))
struct RecordReplayTests {
    static let bench = WorkoutRepositoryContract.exercises[0]
    static let squat = WorkoutRepositoryContract.exercises[2]

    /// Workout `number`, started `day` days from `EventBuilders.start` and an hour long.
    static func session(_ number: Int, day: Double, _ exercises: [Seeders.ExerciseLog]) -> WorkoutState {
        let start = EventBuilders.start.addingTimeInterval(86400 * day)
        return Seeders.workout(number: number, endedAt: WorkoutRepositoryContract.ending(startedAt: start), exercises)
    }

    static func lift(_ exercise: Exercise, _ pounds: Decimal..., reps: Int = 5) -> Seeders.ExerciseLog {
        Seeders.ExerciseLog(exercise, pounds.map { Seeders.SetSpec($0, reps) })
    }

    /// Each live workout's `pr_count`, in history's order.
    static let counts = "SELECT pr_count FROM workout WHERE deleted_at IS NULL ORDER BY started_at, id"

    /// Every live record as its columns, in id order: what "the same rows" compares.
    static let records = """
    SELECT id || ' ' || workout_id || ' ' || exercise_id || ' ' || kind || ' ' || weight_e7g || ' ' || quote(reps)
        || ' ' || quote(previous_kind) || ' ' || quote(previous_weight_e7g) || ' ' || quote(previous_reps)
        || ' ' || achieved_at
    FROM personal_record WHERE deleted_at IS NULL ORDER BY id
    """

    @Test("Each write keeps every workout's pr_count equal to its live records: the 2,250 lb typo, fixed and undone")
    func recordCounts_followEveryWrite() async throws {
        let repositories = try Repositories()
        let first = Self.session(0, day: -6, [Self.lift(Self.bench, 200)])
        let typo = Self.session(1, day: -4, [Self.lift(Self.bench, 2250, 200)])
        let last = Self.session(2, day: -2, [Self.lift(Self.bench, 230)])
        for workout in [first, typo, last] {
            try await repositories.history.materialize(workout)
        }
        #expect(try await repositories.texts(Self.counts) == ["0", "2", "0"])
        var sets = typo.exercises[0].sets
        sets[0].weight = .pounds(225)
        try await repositories.workouts.updateSets(workoutExerciseID: typo.exercises[0].id, sets: sets)
        #expect(try await repositories.texts(Self.counts) == ["0", "2", "2"])
        // The typo's two records changed value in their own rows: no row was added or deleted for them.
        let typoRows = "SELECT COUNT(*) FROM personal_record WHERE workout_id = ?"
        #expect(try await repositories.count(typoRows, [ColumnCodec.text(typo.id)]) == 2)
        sets[0].weight = .pounds(195)
        sets[1].weight = .pounds(190)
        try await repositories.workouts.updateSets(workoutExerciseID: typo.exercises[0].id, sets: sets)
        #expect(try await repositories.texts(Self.counts) == ["0", "0", "2"])
        try await repositories.workouts.delete(id: first.id)
        #expect(try await repositories.texts(Self.counts) == ["0", "2"])
        try await repositories.history.materialize(first)
        #expect(try await repositories.texts(Self.counts) == ["0", "0", "2"])
    }

    @Test("A deleted workout brought back without the lift it set records with counts none")
    func revivedWorkout_countsItsRecordsAgain() async throws {
        let repositories = try Repositories()
        let first = Self.session(0, day: -4, [Self.lift(Self.bench, 200)])
        let second = Self.session(1, day: -2, [Self.lift(Self.bench, 210)])
        try await repositories.history.materialize(first)
        try await repositories.history.materialize(second)
        try await repositories.workouts.delete(id: second.id)
        var rebuilt = second
        rebuilt.exercises = [Self.session(1, day: -2, [Self.lift(Self.squat, 100)]).exercises[0]]
        try await repositories.history.materialize(rebuilt)
        let count = "SELECT pr_count FROM workout WHERE id = ?"
        #expect(try await repositories.texts(count, [ColumnCodec.text(second.id)]) == ["0"])
        #expect(try await repositories.stats.personalRecords(exerciseID: Self.bench.id) == [])
    }

    @Test("A rebuild that moves a workout later detects records again from the place it left")
    func movedWorkout_redetectsFromItsOldPlace() async throws {
        let repositories = try Repositories()
        let moved = Self.session(0, day: -6, [Self.lift(Self.bench, 200)])
        let other = Self.session(1, day: -4, [Self.lift(Self.bench, 210)])
        try await repositories.history.materialize(moved)
        try await repositories.history.materialize(other)
        #expect(try await repositories.stats.personalRecords(exerciseID: Self.bench.id).count == 2)
        var later = Self.session(0, day: -2, [Self.lift(Self.bench, 200)])
        later.exercises = moved.exercises
        try await repositories.history.materialize(later)
        // The other workout is now the first of the lift, and 200 lb after 210 lb is no record.
        #expect(try await repositories.stats.personalRecords(exerciseID: Self.bench.id) == [])
        #expect(try await repositories.texts(Self.counts) == ["0", "0"])
    }

    @Test("A rebuild that drops an exercise detects that exercise's records again in the workouts after it")
    func droppedExercise_redetectsItsLaterWorkouts() async throws {
        let repositories = try Repositories()
        let first = Self.session(0, day: -4, [Self.lift(Self.bench, 200), Self.lift(Self.squat, 100)])
        let second = Self.session(1, day: -2, [Self.lift(Self.bench, 210), Self.lift(Self.squat, 110)])
        try await repositories.history.materialize(first)
        try await repositories.history.materialize(second)
        #expect(try await repositories.texts(Self.counts) == ["0", "4"])
        var benchOnly = first
        benchOnly.exercises.removeLast()
        try await repositories.history.materialize(benchOnly)
        #expect(try await repositories.stats.personalRecords(exerciseID: Self.squat.id) == [])
        #expect(try await repositories.stats.personalRecords(exerciseID: Self.bench.id).count == 2)
        #expect(try await repositories.texts(Self.counts) == ["0", "2"])
    }
}

/// The scope of an edit, determinism, and damage.
extension RecordReplayTests {
    @Test("An edit reads and writes only its exercise's records, from its own workout on")
    func edit_touchesOnlyItsExercise_fromItsWorkoutOn() async throws {
        let repositories = try Repositories()
        let workouts = [200, 210, 220].enumerated().map { index, pounds in
            Self.session(index, day: Double(2 * index - 6), [
                Self.lift(Self.bench, Decimal(pounds)), Self.lift(Self.squat, Decimal(pounds - 100))
            ])
        }
        for workout in workouts {
            try await repositories.history.materialize(workout)
        }
        let before = try await repositories.texts("SELECT id || updated_at FROM personal_record ORDER BY id")
        repositories.clock.advance()
        var sets = workouts[1].exercises[0].sets
        sets[0].weight = .pounds(215)
        let statements = try await repositories.statements(startingWith: "") {
            try await repositories.workouts.updateSets(workoutExerciseID: workouts[1].exercises[0].id, sets: sets)
        }
        // The edited workout's two bench records and the last one's (now over 215) changed; nothing else did.
        let changed = "SELECT workout_id FROM personal_record WHERE updated_at = ? ORDER BY workout_id"
        #expect(try await repositories.texts(changed, [repositories.clock.timestamp]) == [
            workouts[1], workouts[1], workouts[2], workouts[2]
        ].map { ColumnCodec.text($0.id) })
        let after = try await repositories.texts("SELECT id || updated_at FROM personal_record ORDER BY id")
        #expect(Set(before).subtracting(after).count == 4)
        #expect(!statements.contains { $0.contains(ColumnCodec.text(Self.squat.id)) }, "the squat was read")
        #expect(!statements.contains { $0.contains(ColumnCodec.text(workouts[0].id)) }, "the first was read")
    }

    @Test("One history gives the same record rows and counts in any store order, and one edit the same statements")
    func sameHistory_sameRows_sameStatements() async throws {
        var generator = SeededGenerator(seed: 27)
        let history = Seeders.history(
            exercises: Array(WorkoutRepositoryContract.exercises.prefix(3)),
            workouts: 12,
            setsPerWorkout: 6,
            rng: &generator
        )
        var shuffled = history
        shuffled.shuffle(using: &generator)
        var rows: [[String]] = []
        var statements: [[String]] = []
        for order in [history, history.reversed(), shuffled, history] {
            let repositories = try Repositories()
            for workout in order {
                try await repositories.history.materialize(workout)
            }
            try await rows.append(repositories.texts(Self.records) + repositories.texts(Self.counts))
            var sets = history[2].exercises[0].sets
            sets[0].weight = .pounds(400)
            try await statements.append(repositories.statements(startingWith: "") {
                try await repositories.workouts.updateSets(workoutExerciseID: history[2].exercises[0].id, sets: sets)
            })
        }
        #expect(rows[0].count > 12, "the history sets records")
        #expect(rows.allSatisfy { $0 == rows[0] })
        // Two stores built the same way, edited the same way, run the same statements in the same order.
        #expect(statements[3] == statements[0])
    }

    @Test("A damaged set of the lift in a later workout fails the replay by name and writes nothing; others do not")
    func damagedLaterWorkout_failsTheReplay() async throws {
        let repositories = try Repositories()
        let first = Self.session(0, day: -6, [Self.lift(Self.bench, 200), Self.lift(Self.squat, 100)])
        let damaged = Self.session(1, day: -4, [Self.lift(Self.bench, 210), Self.lift(Self.squat, 110)])
        try await repositories.history.materialize(first)
        try await repositories.history.materialize(damaged)
        try await repositories.execute(
            "UPDATE logged_set SET weight_e7g = 'heavy' WHERE id = ?",
            [ColumnCodec.text(damaged.exercises[0].sets[0].id)]
        )
        let rows = """
        SELECT id || updated_at || quote(deleted_at) FROM personal_record UNION ALL SELECT pr_count FROM workout
        """
        let before = try await repositories.texts(rows)
        repositories.clock.advance()
        var lighter = first.exercises[0].sets
        lighter[0].weight = .pounds(190)
        let weight = LedgerPersistenceError.malformedColumn("logged_set.weight_e7g")
        await #expect(throws: weight) {
            try await repositories.workouts.updateSets(workoutExerciseID: first.exercises[0].id, sets: lighter)
        }
        // A new workout of the lift is judged against the damaged set: refused too, and nothing stored.
        let next = Self.session(2, day: -2, [Self.lift(Self.bench, 220)])
        await #expect(throws: weight) { try await repositories.history.materialize(next) }
        #expect(try await repositories.texts(rows) == before)
        #expect(try await repositories.workouts.workout(id: first.id) == first)
        // The squat's history is readable: its edit goes through.
        var squatSets = first.exercises[1].sets
        squatSets[0].weight = .pounds(90)
        try await repositories.workouts.updateSets(workoutExerciseID: first.exercises[1].id, sets: squatSets)
        // Materialising the damaged workout again repairs it, and the bench edit goes through.
        try await repositories.history.materialize(damaged)
        try await repositories.workouts.updateSets(workoutExerciseID: first.exercises[0].id, sets: lighter)
        #expect(try await repositories.texts(Self.counts) == ["0", "4"])
        // Reps below 1 are damage too, by name.
        try await repositories.damage(
            "UPDATE logged_set SET reps = 0 WHERE id = ?",
            [ColumnCodec.text(damaged.exercises[0].sets[0].id)]
        )
        await #expect(throws: LedgerPersistenceError.malformedColumn("logged_set.reps")) {
            try await repositories.workouts.updateSets(
                workoutExerciseID: first.exercises[0].id,
                sets: first.exercises[0].sets
            )
        }
    }
}
