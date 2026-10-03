import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 close-out round: the fixes of S3-1 (a record naming another workout is refused) and S3-2 (a write
/// diffs a workout's children whatever the state of the rows above them), attacked for regressions, as S2-5
/// was a regression of S2-1's fix.
///
/// F05 records follow-up (product decision #27): records are detected by the repository, never given, so S3-1's
/// refusal is gone with the `prs` argument, and its test with it. Each test stores `S3Kit.baseline` first, so a
/// mixed workout holds records, and gives no records itself.
@Suite("Adversarial S3 close-out · record owners and the children diff", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutFixCloseoutAdversarialTests {
    static let first = S3Kit.mixed(1, endedAt: S3Kit.day(-1))
    static let second = S3Kit.mixed(2)

    @Test("A rebuild repairs a workout's damaged record rows: the records read back, two live rows", arguments: [
        "kind = 'best'", "achieved_at = 'noon'", "weight_e7g = 1.5", "previous_kind = 'weightAtReps'", "id = 'nope'",
        "id = CAST(id AS BLOB)", "id = lower(id)", "workout_id = 'nope'", "deleted_at = updated_at", "exercise_id = 7"
    ])
    func damagedRecordRows_areRepaired(damage: String) async throws {
        let stack = try await S3Kit.stack()
        let records = S3Kit.mixedRecords(of: Self.first)
        try await stack.materialize(S3Kit.baseline)
        try await stack.materialize(Self.second)
        try await stack.materialize(Self.first) // before the second, which then ties with it and sets none
        try await stack.damage("UPDATE personal_record SET \(damage) WHERE workout_id = ? AND kind = 'weightAtReps'", [
            Self.first.id.rawValue.uuidString
        ])
        stack.clock.advance()
        try await stack.materialize(Self.first)
        let read = try await stack.stats().personalRecords(exerciseID: S3Kit.bench)
        #expect(read == records)
        let all = [S3Kit.baseline, Self.first, Self.second]
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts(all, records: 2))
        #expect(try await stack.texts("SELECT pr_count FROM workout ORDER BY ended_at") == ["0", "2", "0"])
    }

    @Test("A second delete writes nothing; a delete also clears live rows left under a parent deleted alone")
    func delete_isIdempotent_andClearsLeftovers() async throws {
        let stack = try await S3Kit.stack()
        try await stack.materialize(S3Kit.baseline)
        try await stack.materialize(Self.second)
        stack.clock.advance()
        try await stack.workouts.delete(id: Self.second.id)
        let deleted = try await stack.dump()
        stack.clock.advance()
        try await stack.workouts.delete(id: Self.second.id)
        #expect(try await stack.dump() == deleted, "a second delete stamped rows")
        // Brought back, then its row deleted alone: the children are live under a deleted workout row.
        try await stack.materialize(Self.second)
        try await stack.execute(
            "UPDATE workout SET deleted_at = updated_at WHERE id = ?",
            [Self.second.id.rawValue.uuidString]
        )
        try await stack.workouts.delete(id: Self.second.id)
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts([S3Kit.baseline]))
        try await stack.materialize(Self.second)
        #expect(try await stack.workouts.workout(id: Self.second.id) == Self.second)
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts([S3Kit.baseline, Self.second], records: 2))
    }

    /// The newest `updated_at` among the rows of workout `number`, in its four tables.
    static func lastStamp(of workout: WorkoutState, in stack: S3Kit.Stack) async throws -> [String] {
        try await stack.texts("""
        SELECT MAX(updated_at) FROM workout WHERE id = :id
        UNION ALL SELECT MAX(updated_at) FROM workout_exercise WHERE workout_id = :id
        UNION ALL SELECT MAX(logged_set.updated_at) FROM logged_set
            JOIN workout_exercise ON workout_exercise.id = workout_exercise_id WHERE workout_id = :id
        UNION ALL SELECT MAX(updated_at) FROM personal_record WHERE workout_id = :id
        """, ["id": workout.id.rawValue.uuidString])
    }

    @Test(
        "A rebuild, an edit or a delete of a workout with parents deleted alone writes no row of another workout",
        arguments: ["rebuild", "edit", "delete"]
    )
    func repairs_touchOnlyTheirOwnWorkout(write: String) async throws {
        let stack = try await S3Kit.stack()
        try await stack.materialize(S3Kit.baseline)
        try await stack.materialize(Self.first)
        try await stack.materialize(Self.second)
        let id = Self.second.id.rawValue.uuidString
        try await stack.execute(
            "UPDATE workout_exercise SET deleted_at = updated_at WHERE workout_id = ? AND position = 0",
            [id]
        )
        try await stack.execute("UPDATE workout_exercise SET deleted_at = updated_at WHERE position = 1")
        let stamps = try await Self.lastStamp(of: Self.first, in: stack)
        stack.clock.advance()
        var expected: WorkoutState? = Self.second
        switch write {
        case "rebuild":
            try await stack.materialize(Self.second)
        case "edit":
            // Row 1 was deleted alone in both workouts; the strict read sees no live row, so the edit names none.
            try await stack.execute(
                "UPDATE workout_exercise SET deleted_at = NULL WHERE workout_id = ? AND position = 1",
                [id]
            )
            try await stack.workouts.updateSets(workoutExerciseID: Self.second.exercises[1].id, sets: [])
            expected?.exercises = [Self.second.exercises[1]]
            expected?.exercises[0].sets = []
        default:
            try await stack.workouts.delete(id: Self.second.id)
            expected = nil
        }
        #expect(try await stack.workouts.workout(id: Self.second.id) == expected)
        let live = try await stack.texts("""
        SELECT COUNT(*) FROM logged_set JOIN workout_exercise ON workout_exercise.id = workout_exercise_id
        WHERE workout_id = ? AND logged_set.deleted_at IS NULL
        """, [id])
        #expect(live == ["\(expected?.totalSets ?? 0)"], "sets the workout lacks are live")
        // The other workout's rows keep their stamps, and its own damage: one exercise row still deleted alone.
        #expect(try await Self.lastStamp(of: Self.first, in: stack) == stamps)
        #expect(try await stack.workouts.workout(id: Self.first.id)?.exercises == [Self.first.exercises[0]])
    }
}
