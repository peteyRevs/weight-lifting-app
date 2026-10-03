import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: damage the implementer's 23 cases do not hold. The notes' rule (decision 16):
/// a damaged workout throws or is left out, never reads as another value, and "materialising the workout
/// again repairs it".
@Suite("Adversarial S3 · damaged history rows", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutRepairAdversarialTests {
    /// Finding S3-2. A write reads the stored rows through the live workout row and the live exercise rows.
    /// When one of those is soft-deleted on its own, the live rows under it are never seen, so never removed.
    @Test(
        "A materialisation repairs a workout whose row, or one of whose exercise rows, was soft-deleted alone",
        arguments: ["UPDATE workout SET deleted_at = updated_at", "UPDATE workout_exercise SET deleted_at = updated_at"]
    )
    func loneSoftDelete_isRepaired(damage: String) async throws {
        let stack = try await S3Kit.stack()
        let first = S3Kit.mixed(1)
        try await stack.materialize(first)
        try await stack.execute(damage)
        var rebuilt = first
        rebuilt.exercises.removeLast()
        rebuilt.exercises[0].sets.removeLast(3)
        try await stack.materialize(rebuilt)
        #expect(try await stack.workouts.workout(id: first.id) == rebuilt)
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts([rebuilt]), "rows the workout lacks are live")
        #expect(try await stack.stats().weeklyVolume(in: .distantPast ..< .distantFuture) == rebuilt.volume)
    }

    /// Finding S3-3. An id stored as a blob of its own text passes `ColumnReader.identifier`, but SQL compares
    /// it with its children's text `…_id` and finds none.
    @Test("An exercise row whose id is a blob fails the read, or reads whole: never without its sets")
    func blobExerciseID_neverReadsAsAnEmptyExercise() async throws {
        let stack = try await S3Kit.stack()
        let first = S3Kit.mixed(1)
        try await stack.materialize(first)
        try await stack.damage("UPDATE workout_exercise SET id = CAST(id AS BLOB) WHERE position = 0")
        let read = try? await stack.workouts.workout(id: first.id)
        #expect(read == nil || read == first, "read with sets \(String(describing: read?.exercises.map(\.sets.count)))")
        let listed = try await stack.workouts.recent(limit: 5)
        #expect(listed == [] || listed == [first])
        // A write still repairs the row, as for any damaged id (S2-3).
        try await stack.materialize(first)
        #expect(try await stack.workouts.workout(id: first.id) == first)
        #expect(try await stack.stats().weeklyVolume(in: .distantPast ..< .distantFuture) == first.volume)
    }

    @Test("A workout row whose id is a blob is left out, or reads whole; a new materialisation stores it once")
    func blobWorkoutID_neverReadsAsAnEmptyWorkout() async throws {
        let stack = try await S3Kit.stack()
        let first = S3Kit.mixed(1)
        try await stack.materialize(first)
        try await stack.damage("UPDATE workout SET id = CAST(id AS BLOB)")
        let listed = try await stack.workouts.recent(limit: 5)
        #expect(listed == [] || listed == [first], "listed with \(listed.map(\.exercises.count)) exercises")
        try await stack.materialize(first)
        #expect(try await stack.workouts.recent(limit: 5) == [first], "the workout is listed twice")
    }

    @Test("A soft-deleted row under a live parent stays hidden from every read and query, and is revived by id")
    func deletedChildren_areHidden() async throws {
        let stack = try await S3Kit.stack()
        let first = S3Kit.mixed(1)
        try await stack.materialize(first)
        let dropID = first.exercises[0].sets[3].id
        try await stack.execute(
            "UPDATE logged_set SET deleted_at = updated_at WHERE id = ?",
            [dropID.rawValue.uuidString]
        )
        var without = first
        without.exercises[0].sets.remove(at: 3)
        #expect(try await stack.workouts.workout(id: first.id) == without)
        #expect(try await stack.stats().weeklyVolume(in: .distantPast ..< .distantFuture) == without.volume)
        try await stack.materialize(first)
        #expect(try await stack.workouts.workout(id: first.id) == first)
        #expect(try await S2Kit.count(stack.queue, "logged_set") == first.totalSets)
    }
}
