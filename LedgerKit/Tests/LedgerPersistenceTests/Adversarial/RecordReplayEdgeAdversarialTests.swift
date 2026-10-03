import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 records follow-up (product decision #27), adversarial round 1: the replay at its edges: one final history
/// reached by different writes, weights at the end of the column, and damaged history (notes, open question 2).
@Suite("Adversarial records · replay edges", .tags(.persistence), .timeLimit(.minutes(1)))
struct RecordReplayEdgeAdversarialTests {
    /// The live record rows and record counts, without their stamps.
    static func derived(_ stack: S3Kit.Stack) async throws -> [String] {
        try await stack.texts("""
        SELECT id || ' ' || workout_id || ' ' || exercise_id || ' ' || kind || ' ' || weight_e7g || ' ' ||
            quote(reps) || ' ' || quote(previous_kind) || ' ' || quote(previous_weight_e7g) || ' ' ||
            quote(previous_reps) || ' ' || achieved_at
        FROM personal_record WHERE deleted_at IS NULL
        UNION ALL SELECT id || ' ' || pr_count FROM workout WHERE deleted_at IS NULL
        ORDER BY 1
        """)
    }

    static func bench(_ number: Int, day: Double, _ sets: [S3Kit.SetSpec], deload: Bool = false) -> WorkoutState {
        var workout = S3Kit.workout(number, endedAt: S3Kit.day(day), [S3Kit.RowSpec(S3Kit.bench, sets)])
        workout.isDeload = deload
        return workout
    }

    @Test("One final history gives the same record rows and counts, whatever writes, rebuilds and deletes led to it")
    func finalHistory_decidesTheRows() async throws {
        let final = [
            Self.bench(1, day: -6, [S3Kit.set(100, 5)]),
            Self.bench(2, day: -4, [S3Kit.set(110, 5), S3Kit.set(120, 1)], deload: true),
            Self.bench(3, day: -4, [S3Kit.set(115, 5)]),
            Self.bench(4, day: -1, [S3Kit.set(125, 3), S3Kit.set(105, 8, .added)])
        ]
        let direct = try await S3Kit.stack()
        for workout in final {
            try await direct.materialize(workout)
        }
        let winding = try await S3Kit.stack()
        try await winding.materialize(Self.bench(4, day: -9, [S3Kit.set(500, 5)])) // first, at another start
        try await winding.materialize(final[2])
        try await winding.materialize(Self.bench(5, day: -5, [S3Kit.set(130, 12)]))
        try await winding.materialize(final[0])
        try await winding.workouts.delete(id: S3Kit.workoutID(3))
        try await winding.materialize(Self.bench(2, day: -7, [S3Kit.set(90, 5)]))
        try await winding.workouts.delete(id: S3Kit.workoutID(5))
        try await winding.materialize(final[3]) // moved later
        try await winding.materialize(final[2]) // revived
        try await winding.materialize(final[1]) // moved, and now a deload
        let rows = try await Self.derived(direct)
        #expect(rows.count == 4 + 4, "four records (two each by workouts 3 and 4; the deload sets none), four counts")
        #expect(RecordOracle.replay(final).values.map(\.count).reduce(0, +) == 4)
        #expect(try await Self.derived(winding) == rows)
    }

    @Test("Weights at the end of the column: one unit apart is a weight record, the same gram's estimate is not")
    func extremeWeights_compareExactly() async throws {
        let stack = try await S3Kit.stack()
        let heavy = Int64.max - 100_000_000
        var first = Self.bench(1, day: -2, [S3Kit.set(1, 1)])
        first.exercises[0].sets[0].weight = Weight(e7g: heavy)
        var second = Self.bench(2, day: -1, [S3Kit.set(1, 1)])
        second.exercises[0].sets[0].weight = Weight(e7g: heavy + 1)
        try await stack.materialize(first)
        try await stack.materialize(second)
        let records = try await stack.stats().personalRecords(exerciseID: S3Kit.bench)
        #expect(records.map(\.kind) == [.weightAtReps(Weight(e7g: heavy + 1), .one)])
        let bests = try await stack.stats().bests(
            before: S3Kit.workout(9, [S3Kit.RowSpec(S3Kit.bench, [])]),
            for: [S3Kit.bench]
        )
        #expect(bests.weightAtReps[S3Kit.bench] == [.one: Weight(e7g: heavy + 1)])
        #expect(bests.e1RM[S3Kit.bench] == OneRepMax.brzycki(weight: Weight(e7g: heavy), reps: .one))
    }

    /// Notes, open question 2, decided by the orchestrator (R-Q1, fix round 1: skip and log). The replay leaves out
    /// a workout it cannot read, as the lists do: every write of the lift goes through, judged against the readable
    /// history, and the damaged workout's own records stay as they are. The damaged workout is still in no list
    /// and `workout(id:)` throws; a `delete(id:)` of it, by id, still works. (Sanctioned edit: this pinned the
    /// strict read, "(documents)", and now pins the decision; everything else it checks is kept.)
    @Test("A damaged set of a lift leaves its workout out of the replay; every write goes through (decision on R-Q1)")
    func damagedHistory_isLeftOutOfWritesOfItsLift() async throws {
        let stack = try await S3Kit.stack()
        let damaged = Self.bench(1, day: -6, [S3Kit.set(100, 5)])
        try await stack.materialize(damaged)
        try await stack.materialize(Self.bench(2, day: -3, [S3Kit.set(105, 5)]))
        try await stack.execute("UPDATE logged_set SET reps = 0 WHERE workout_exercise_id = ?", [
            damaged.exercises[0].id.rawValue.uuidString
        ])
        stack.clock.advance()
        let records = { try await stack.stats().personalRecords(exerciseID: S3Kit.bench) }
        try await stack.materialize(Self.bench(3, day: -1, [S3Kit.set(110, 5)]))
        #expect(try await records().filter { $0.workoutID == S3Kit.workoutID(3) }.count == 2, "110 over 105")
        try await stack.materialize(Self.bench(4, day: -8, [S3Kit.set(90, 5)]))
        try await stack.workouts.updateSets(workoutExerciseID: S3Kit.rowID(2, 0), sets: [])
        // Workout 4 is the first readable bench, workout 2 has no sets left, and 110 beats 90.
        #expect(try await records().map(\.workoutID) == [S3Kit.workoutID(3), S3Kit.workoutID(3)])
        let squat = S3Kit.workout(5, [S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(225, 5)])])
        try await stack.materialize(squat)
        #expect(try await stack.workouts.recent(limit: 5).map(\.id) == [
            squat.id, S3Kit.workoutID(3), S3Kit.workoutID(2), S3Kit.workoutID(4)
        ])
        await #expect(throws: LedgerPersistenceError.self) { _ = try await stack.workouts.workout(id: damaged.id) }
        try await stack.workouts.delete(id: damaged.id)
        try await stack.materialize(Self.bench(3, day: -1, [S3Kit.set(110, 5)]))
        #expect(try await records().count == 2)
    }

    /// Round 1's `edit_recomputesDerivedColumns_andStampsOnlyChanges` lost its record half when records became
    /// detected (the workout it edits now has none): this puts it back.
    @Test("An edit that changes no record leaves every record row's stamp, and other workouts' counts and stamps")
    func editChangingNoRecord_stampsNoRecord() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1)
        let later = S3Kit.workout(2, endedAt: S3Kit.day(1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(200, 5)])])
        for stored in [S3Kit.baseline, workout, later] {
            try await stack.materialize(stored)
        }
        let records = try await stack.texts("SELECT id || ' ' || updated_at FROM personal_record ORDER BY id")
        let workouts = try await stack
            .texts("SELECT id || ' ' || pr_count || ' ' || updated_at FROM workout ORDER BY id")
        #expect(records.count == 4)
        stack.clock.advance()
        var squat = workout.exercises[1].sets
        squat[0].weight = .pounds(230) // 13 reps: no estimate, and no history at 13 reps or more
        try await stack.workouts.updateSets(workoutExerciseID: workout.exercises[1].id, sets: squat)
        var bench = workout.exercises[0].sets
        bench[4].weight = .pounds(135) // the warm-up
        try await stack.workouts.updateSets(workoutExerciseID: workout.exercises[0].id, sets: bench)
        #expect(try await stack.texts("SELECT id || ' ' || updated_at FROM personal_record ORDER BY id") == records)
        let after = try await stack.texts("SELECT id || ' ' || pr_count || ' ' || updated_at FROM workout ORDER BY id")
        #expect(after.filter { !$0.hasPrefix(workout.id.rawValue.uuidString) }
            == workouts.filter { !$0.hasPrefix(workout.id.rawValue.uuidString) })
    }

    /// Notes, open question 4: records written before the follow-up (the v001 fixture's were given by the caller)
    /// are replaced when their workout is next written, even one naming a lift the workout no longer has.
    @Test("A stray record row of a lift the workout lacks is dropped by the workout's next write, and recounted")
    func strayRecord_isDroppedByTheNextWrite() async throws {
        let stack = try await S3Kit.stack()
        let workout = Self.bench(1, day: -1, [S3Kit.set(100, 5)])
        try await stack.materialize(workout)
        try await stack.execute("""
        INSERT INTO personal_record
            (id, workout_id, exercise_id, kind, weight_e7g, reps, achieved_at, created_at, updated_at)
        VALUES ('stray', ?, ?, 'weightAtReps', 1, 5, 0, 'a', 'a')
        """, [workout.id.rawValue.uuidString, S3Kit.squat.rawValue.uuidString])
        try await stack.execute("UPDATE workout SET pr_count = 1")
        #expect(try await stack.stats().personalRecords(exerciseID: S3Kit.squat).count == 1)
        try await stack.materialize(workout)
        #expect(try await stack.stats().personalRecords(exerciseID: S3Kit.squat) == [])
        #expect(try await stack.texts("SELECT pr_count FROM workout") == ["0"])
    }
}
