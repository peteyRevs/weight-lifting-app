import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Invalid stored history is surfaced as an error or left out, never a crash and never a rounded value: every
/// column is read strictly. A workout is one aggregate, so a damaged row anywhere in it makes `workout(id:)`
/// throw by name, while the lists leave that workout out and keep the rest. The row is kept, and materialising
/// the workout again repairs it, since a write compares stored rows as column values and never decodes them.
@Suite("GRDBWorkoutRepository · invalid stored data", .tags(.persistence), .timeLimit(.minutes(1)))
struct DamagedWorkoutRowTests {
    /// An `UPDATE` of one row of the stored contract workout, and what reading the workout must throw.
    struct Damage: Sendable, CustomStringConvertible {
        let description: String
        let surfaced: LedgerPersistenceError
    }

    static let workout = WorkoutRepositoryContract.workout()
    static let other = WorkoutRepositoryContract.workout(number: 1, endedAt: EventBuilders.start.addingTimeInterval(60))

    static func root(_ assignment: String, _ column: String) -> Damage {
        Damage(
            description: "workout SET \(assignment) WHERE id = '\(ColumnCodec.text(workout.id))'",
            surfaced: .malformedColumn("workout.\(column)")
        )
    }

    /// A damage to the workout's first exercise row.
    static func exercise(_ assignment: String, _ column: String) -> Damage {
        Damage(
            description: "workout_exercise SET \(assignment) WHERE id = '\(ColumnCodec.text(workout.exercises[0].id))'",
            surfaced: .malformedColumn("workout_exercise.\(column)")
        )
    }

    /// A damage to the second set of the workout's third exercise.
    static func set(_ assignment: String, _ surfaced: LedgerPersistenceError) -> Damage {
        let id = ColumnCodec.text(workout.exercises[2].sets[1].id)
        return Damage(description: "logged_set SET \(assignment) WHERE id = '\(id)'", surfaced: surfaced)
    }

    static let damages = [
        root("started_at = 'yesterday'", "started_at"),
        root("ended_at = x'00'", "ended_at"),
        root("phase = 'paused'", "phase"),
        root("units = 'stone'", "units"),
        root("is_deload = 'yes'", "is_deload"),
        root("name = x'80'", "name"),
        root("week_index = 2", "program_id"), // a source with no program or day
        root("week_index = 2.5, program_id = id, day_template_id = id", "week_index"),
        Damage(
            description: "workout SET origin_device = 'nope' WHERE id = '\(ColumnCodec.text(workout.id))'",
            surfaced: .malformedIdentifier("nope")
        ),
        exercise("rest_seconds = 100", "rest_seconds"),
        exercise("rpe_x2 = 7", "rpe_x2"),
        exercise("equipment = 'sled'", "equipment"),
        exercise("step_e7g = 1.5", "step_e7g"),
        exercise("target_sets = 'five'", "target_sets"),
        exercise("target_load_e7g = 9.3e18", "target_load_e7g"),
        exercise("position = x'01'", "position"),
        set("reps = 0", .malformedColumn("logged_set.reps")),
        set("reps = 4.5", .malformedColumn("logged_set.reps")),
        set("weight_e7g = 0.5", .malformedColumn("logged_set.weight_e7g")),
        set("kind = 'amrap'", .malformedColumn("logged_set.kind")),
        set("done_at = 'noon'", .malformedColumn("logged_set.done_at")),
        set("done_at = 9e999", .malformedColumn("logged_set.done_at")), // +∞
        set("id = x'00'", .malformedIdentifier("\u{0}"))
    ]

    @Test(
        "A damaged row fails workout(id:) by name, leaves the lists the other workouts, is kept, and is repaired",
        arguments: damages
    )
    func damagedRow_failsByID_isLeftOutOfLists_andIsRepaired(_ damage: Damage) async throws {
        let repositories = try await Repositories.withProgramExercises()
        let workouts = repositories.workouts
        try await repositories.history.materialize(Self.workout)
        try await repositories.history.materialize(Self.other)
        try await repositories.execute("UPDATE \(damage)")
        await #expect(throws: damage.surfaced) { try await workouts.workout(id: Self.workout.id) }
        #expect(try await workouts.recent(limit: 5) == [Self.other])
        #expect(try await workouts.workouts(in: .distantPast ..< .distantFuture) == [Self.other])
        var values = workouts.observeRecent(limit: 5).makeAsyncIterator()
        #expect(await values.next() == [Self.other])
        // The damage is kept: nothing was deleted, and the read still fails.
        #expect(try await repositories.count("SELECT COUNT(*) FROM logged_set WHERE deleted_at IS NULL") == 38)
        await #expect(throws: damage.surfaced) { try await workouts.workout(id: Self.workout.id) }
        // An edit needs the whole workout readable; a new materialisation does not.
        await #expect(throws: damage.surfaced) {
            try await workouts.updateSets(
                workoutExerciseID: Self.workout.exercises[4].id,
                sets: Self.workout.exercises[4].sets
            )
        }
        try await repositories.history.materialize(Self.workout)
        #expect(try await workouts.recent(limit: 5) == [Self.other, Self.workout])
    }

    @Test(
        "An exercise or set whose parent names no stored row is damage, not another workout's: a new write repairs it",
        arguments: [
            "UPDATE workout_exercise SET workout_id = 'nope' WHERE id = ?",
            "UPDATE workout_exercise SET workout_id = CAST(workout_id AS BLOB) WHERE id = ?",
            "UPDATE logged_set SET workout_exercise_id = 'nope' WHERE workout_exercise_id = ?"
        ]
    )
    func danglingParent_isRepaired(damage: String) async throws {
        let repositories = try await Repositories.withProgramExercises()
        try await repositories.history.materialize(Self.workout)
        try await repositories.damage(damage, [ColumnCodec.text(Self.workout.exercises[1].id)])
        #expect(try await repositories.workouts.workout(id: Self.workout.id) != Self.workout)
        try await repositories.history.materialize(Self.workout)
        #expect(try await repositories.workouts.workout(id: Self.workout.id) == Self.workout)
    }
}

/// Blob ids, and damaged values under the stats queries.
extension DamagedWorkoutRowTests {
    @Test("An exercise row whose id is a blob fails the read by name, never reads without its sets, and is repaired")
    func blobExerciseID_isDamage() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let workouts = repositories.workouts
        try await repositories.history.materialize(Self.workout)
        try await repositories.history.materialize(Self.other)
        try await repositories.damage(
            "UPDATE workout_exercise SET id = CAST(id AS BLOB) WHERE id = ?",
            [ColumnCodec.text(Self.workout.exercises[0].id)]
        )
        await #expect(throws: LedgerPersistenceError.malformedColumn("workout_exercise.id")) {
            try await workouts.workout(id: Self.workout.id)
        }
        #expect(try await workouts.recent(limit: 5) == [Self.other])
        try await repositories.history.materialize(Self.workout)
        #expect(try await workouts.recent(limit: 5) == [Self.other, Self.workout])
        let all = Date.distantPast ..< Date.distantFuture
        #expect(try await repositories.stats.weeklyVolume(in: all) == Self.workout.volume + Self.other.volume)
    }

    @Test("A workout row whose id is a blob is left out of every list and count, kept, and never listed twice")
    func blobWorkoutID_isDamage() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let workouts = repositories.workouts
        let all = Date.distantPast ..< Date.distantFuture
        try await repositories.history.materialize(Self.workout)
        try await repositories.history.materialize(Self.other)
        try await repositories.damage(
            "UPDATE workout SET id = CAST(id AS BLOB) WHERE id = ?",
            [ColumnCodec.text(Self.workout.id)]
        )
        #expect(try await workouts.workout(id: Self.workout.id) == nil)
        #expect(try await workouts.recent(limit: 5) == [Self.other])
        #expect(try await workouts.workouts(in: all) == [Self.other])
        #expect(try await repositories.stats.sessionsCompleted(in: all) == 1)
        #expect(try await repositories.stats.weeklyVolume(in: all) == Self.other.volume)
        // A new materialisation stores the workout under its text id, beside the blob row, which stays.
        try await repositories.history.materialize(Self.workout)
        #expect(try await workouts.recent(limit: 5) == [Self.other, Self.workout])
        #expect(try await repositories.stats.sessionsCompleted(in: all) == 2)
        #expect(try await repositories.stats.weeklyVolume(in: all) == Self.workout.volume + Self.other.volume)
        #expect(try await repositories.count("SELECT COUNT(*) FROM workout WHERE typeof(id) = 'blob'") == 1)
    }

    @Test("A stats query over a damaged value throws by name; it never reads it as a rounded number")
    func damagedValue_failsTheStatsQuery() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let stats = repositories.stats
        let bench = Self.workout.exercises[0]
        let key = ColumnCodec.text(bench.sets[0].id)
        let everything = Date.distantPast ..< Date.distantFuture
        let calendar = try StatsQueriesContract.calendar
        try await repositories.history.materialize(Self.workout)

        try await repositories.execute("UPDATE logged_set SET e1rm_e7g = 950000000000.5 WHERE id = ?", [key])
        let estimate = LedgerPersistenceError.malformedColumn("logged_set.e1rm_e7g")
        await #expect(throws: estimate) { try await stats.bestE1RM(exerciseID: bench.exerciseID) }
        await #expect(throws: estimate) {
            try await stats.e1RMByWeek(exerciseID: bench.exerciseID, lastWeeks: 8, calendar: calendar)
        }

        try await repositories.execute("UPDATE logged_set SET reps = 5.5 WHERE id = ?", [key])
        let reps = LedgerPersistenceError.malformedColumn("logged_set.reps")
        await #expect(throws: reps) { try await stats.weeklyVolume(in: everything) }

        try await repositories.execute("UPDATE logged_set SET reps = 5, weight_e7g = 'heavy' WHERE id = ?", [key])
        let weight = LedgerPersistenceError.malformedColumn("logged_set.weight_e7g")
        await #expect(throws: weight) { try await stats.bestSet(exerciseID: bench.exerciseID) }
        await #expect(throws: weight) { try await stats.lastPerformance(exerciseID: bench.exerciseID) }
        await #expect(throws: weight) { try await stats.weeklyVolume(in: everything) }

        try await repositories.history.materialize(Self.workout) // repairs the set
        try await repositories.execute("UPDATE workout SET ended_at = 'x'")
        await #expect(throws: LedgerPersistenceError.malformedColumn("workout.ended_at")) {
            try await stats.lastPerformance(exerciseID: bench.exerciseID)
        }
        await #expect(throws: LedgerPersistenceError.malformedColumn("workout.ended_at")) {
            try await stats.e1RMByWeek(exerciseID: bench.exerciseID, lastWeeks: 8, calendar: calendar)
        }
    }

    @Test("A record row or an exercise id that cannot be read is left out of its list, and kept")
    func unreadableListRows_areLeftOut() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let stats = repositories.stats
        let records = WorkoutRepositoryTests.records(of: Self.workout)
        let bench = Self.workout.exercises[0].exerciseID
        try await repositories.history.materialize(Self.workout, prs: records)
        for damage in [
            "kind = 'volume'",
            "reps = 0",
            "previous_kind = 'best'",
            "achieved_at = 'then'",
            "weight_e7g = 1.5",
            "kind = 'volume', id = x'80'" // not even its id can be read, for the log
        ] {
            try await repositories.execute("UPDATE personal_record SET \(damage) WHERE reps IS NOT NULL")
            #expect(try await stats.personalRecords(exerciseID: bench) == [records[0]], "\(damage)")
            #expect(try await repositories.count("SELECT COUNT(*) FROM personal_record WHERE deleted_at IS NULL") == 2)
            try await repositories.history.materialize(Self.workout, prs: records) // repairs or replaces the row
            #expect(try await stats.personalRecords(exerciseID: bench) == records, "\(damage), repaired")
        }
        try await repositories.execute("UPDATE workout_exercise SET exercise_id = 'nope' WHERE position = 3")
        let logged = Self.workout.exercises.map(\.exerciseID).filter { $0 != Self.workout.exercises[3].exerciseID }
        #expect(try await Set(stats.recentlyLogged(limit: 10)) == Set(logged))
    }
}
