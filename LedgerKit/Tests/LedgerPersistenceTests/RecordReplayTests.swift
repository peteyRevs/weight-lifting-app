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

    /// Orchestrator decision on R-SF2: `pr_count` is derived, like `personal_record`, so a recount changes no
    /// synced stamp. Fixing a typo in the first of five workouts changes the counts of the four after it, and none
    /// of their `updated_at`.
    @Test("A recount changes pr_count only: the later workouts' updated_at stays when the first one's typo goes")
    func recount_stampsNoWorkoutRow() async throws {
        let repositories = try Repositories()
        let workouts = (0 ..< 5).map { Self.session(
            $0,
            day: Double(2 * $0 - 10),
            [Self.lift(Self.bench, Decimal(200 + 5 * $0))]
        ) }
        var typo = workouts[0]
        typo.exercises[0].sets[0].weight = .pounds(2250)
        for workout in [typo] + workouts.dropFirst() {
            try await repositories.history.materialize(workout)
        }
        let stamps = "SELECT updated_at FROM workout WHERE id != ? ORDER BY started_at"
        let others: StatementArguments = [ColumnCodec.text(typo.id)]
        let before = try await repositories.texts(stamps, others)
        #expect(try await repositories.texts(Self.counts) == ["0", "0", "0", "0", "0"])
        repositories.clock.advance()
        try await repositories.workouts.updateSets(
            workoutExerciseID: typo.exercises[0].id,
            sets: workouts[0].exercises[0].sets
        )
        #expect(try await repositories.texts(Self.counts) == ["0", "2", "2", "2", "2"])
        #expect(try await repositories.texts(stamps, others) == before)
    }

    /// When the bests' aggregate meets damage it walks the history a workout at a time (`RecordReplay.walkedBests`):
    /// that walk too leaves the damaged workout out, and never counts the asked workout's own stored copy, even one
    /// that started earlier (review R-SF1).
    @Test("Over damaged history, the bests before a workout leave the damaged one out, and never count its own copy")
    func bestsOverDamage_leaveItOut_andNeverCountTheWorkout() async throws {
        let repositories = try Repositories()
        let damaged = Self.session(0, day: -8, [Self.lift(Self.bench, 200)])
        let readable = Self.session(1, day: -6, [Self.lift(Self.bench, 150)])
        let stored = Self.session(2, day: -4, [Self.lift(Self.bench, 300)])
        for workout in [damaged, readable, stored] {
            try await repositories.history.materialize(workout)
        }
        try await repositories.execute(
            "UPDATE logged_set SET weight_e7g = 'heavy' WHERE id = ?",
            [ColumnCodec.text(damaged.exercises[0].sets[0].id)]
        )
        var moved = stored
        moved.startedAt = EventBuilders.start.addingTimeInterval(-86400 * 2)
        let bests = try await repositories.stats.bests(before: moved, for: [Self.bench.id])
        #expect(bests.weightAtReps == [Self.bench.id: [Reps(clamping: 5): .pounds(150)]])
    }

    /// The previous bests of the records `workout` holds of the bench, in list order.
    static func previous(in workout: WorkoutState, _ repositories: Repositories) async throws -> [PRKind?] {
        try await repositories.stats.personalRecords(exerciseID: bench.id).filter { $0.workoutID == workout.id }
            .map(\.previous)
    }

    /// Bench 5 × `pounds` lb, as a record's previous best: the estimate, then the weight.
    static func over(_ pounds: Decimal) -> [PRKind?] {
        let five = Reps(clamping: 5)
        return [
            OneRepMax.brzycki(weight: .pounds(pounds), reps: five).map(PRKind.estimatedOneRepMax),
            .weightAtReps(.pounds(pounds), five)
        ]
    }

    /// Orchestrator decision on R-Q1: the replay leaves out a workout it cannot read, as the lists do, and logs
    /// it. The lifter's writes go through, judged against the readable history; the damaged workout's own record
    /// rows stay as they are until a write repairs it.
    @Test("A lift the replay cannot read is left out: writes go through, judged against the readable history")
    func damagedWorkout_isLeftOutOfTheReplay() async throws {
        let repositories = try Repositories()
        let first = Self.session(0, day: -6, [Self.lift(Self.bench, 200), Self.lift(Self.squat, 100)])
        let damaged = Self.session(1, day: -4, [Self.lift(Self.bench, 210), Self.lift(Self.squat, 110)])
        try await repositories.history.materialize(first)
        try await repositories.history.materialize(damaged)
        let key: StatementArguments = [ColumnCodec.text(damaged.exercises[0].sets[0].id)]
        try await repositories.execute("UPDATE logged_set SET weight_e7g = 'heavy' WHERE id = ?", key)
        let ownRows = "SELECT id || updated_at || weight_e7g FROM personal_record WHERE workout_id = ? ORDER BY id"
        let damagedRows = try await repositories.texts(ownRows, [ColumnCodec.text(damaged.id)])
        repositories.clock.advance()
        var lighter = first.exercises[0].sets
        lighter[0].weight = .pounds(190)
        try await repositories.workouts.updateSets(workoutExerciseID: first.exercises[0].id, sets: lighter)
        #expect(try await repositories.texts(ownRows, [ColumnCodec.text(damaged.id)]) == damagedRows)
        // A new workout of the lift is judged against the readable history: over 190, not the damaged 210.
        let next = Self.session(2, day: -2, [Self.lift(Self.bench, 205)])
        try await repositories.history.materialize(next)
        #expect(try await Self.previous(in: next, repositories) == Self.over(190))
        // Materialising the damaged workout again repairs it: it holds the records, over 190, and the next none.
        try await repositories.history.materialize(damaged)
        #expect(try await Self.previous(in: damaged, repositories) == Self.over(190))
        #expect(try await Self.previous(in: next, repositories) == [])
        // Reps below 1 are left out the same way.
        try await repositories.damage("UPDATE logged_set SET reps = 0 WHERE id = ?", key)
        try await repositories.workouts.updateSets(
            workoutExerciseID: first.exercises[0].id,
            sets: first.exercises[0].sets
        )
        #expect(try await Self.previous(in: next, repositories) == Self.over(200))
        #expect(try await Self.previous(in: damaged, repositories) == Self.over(190))
        // A rebuild of both lifts walks past the damaged bench row to the same workout's squat. Only the damaged lift
        // is left out (review R-2): the readable squat is judged again, over the lighter 80, so its records change.
        let squatRows = "SELECT id || updated_at FROM personal_record WHERE workout_id = ? AND exercise_id = ?"
        let squatKey: StatementArguments = [ColumnCodec.text(damaged.id), ColumnCodec.text(Self.squat.id)]
        let squatBefore = try await repositories.texts(squatRows, squatKey)
        repositories.clock.advance()
        var lighterSquat = first
        lighterSquat.exercises[1].sets[0].weight = .pounds(80)
        try await repositories.history.materialize(lighterSquat)
        let squatAfter = try await repositories.texts(squatRows, squatKey)
        #expect(squatBefore.count == 2)
        #expect(squatAfter != squatBefore)
        // Both records stand, each now over the lightened 80 lb squat.
        let squatPrevious = try await repositories.stats.personalRecords(exerciseID: Self.squat.id)
            .filter { $0.workoutID == damaged.id }.map(\.previous)
        #expect(squatPrevious == Self.over(80))
    }
}
