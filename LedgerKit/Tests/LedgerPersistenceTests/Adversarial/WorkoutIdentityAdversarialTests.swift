import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: the class of S2-1 for history. A write must never move a row out of another
/// workout, whichever table the row is in and whatever state the other workout is in.
@Suite("Adversarial S3 · workout ids", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutIdentityAdversarialTests {
    enum Takeover: String, CaseIterable, Sendable {
        case rowOfALiveWorkout, rowOfADeletedWorkout, removedRow
        case setOfALiveWorkout, setOfADeletedWorkout, removedSet, setUnderARemovedRow
    }

    /// Stores workout 1 in the state `takeover` needs, and returns it as it must still read afterwards
    /// (`nil` when it is deleted).
    static func prepare(_ takeover: Takeover, in stack: S3Kit.Stack) async throws -> WorkoutState? {
        let first = S3Kit.mixed(1, endedAt: S3Kit.day(-1))
        try await stack.materialize(first)
        switch takeover {
        case .rowOfALiveWorkout, .setOfALiveWorkout:
            return first
        case .rowOfADeletedWorkout, .setOfADeletedWorkout:
            try await stack.workouts.delete(id: first.id)
            return nil
        case .removedRow, .setUnderARemovedRow:
            var smaller = first
            smaller.exercises.removeFirst()
            try await stack.materialize(smaller)
            return smaller
        case .removedSet:
            var smaller = first
            smaller.exercises[0].sets.removeFirst()
            try await stack.materialize(smaller)
            return smaller
        }
    }

    /// Workout 2 holding the id `takeover` names: workout 1's first row, or that row's first set.
    static func thief(_ takeover: Takeover) -> (workout: WorkoutState, key: String) {
        var second = S3Kit.mixed(2)
        let victim = S3Kit.mixed(1).exercises[0]
        switch takeover {
        case .rowOfALiveWorkout, .rowOfADeletedWorkout, .removedRow:
            let sets = second.exercises[1].sets
            second.exercises[1] = victim
            second.exercises[1].sets = sets
            return (second, "workout_exercise \(victim.id.rawValue.uuidString)")
        case .setOfALiveWorkout, .setOfADeletedWorkout, .removedSet, .setUnderARemovedRow:
            second.exercises[1].sets[2] = victim.sets[0]
            return (second, "logged_set \(victim.sets[0].id.rawValue.uuidString)")
        }
    }

    @Test(
        "A workout holding another workout's row or set id is refused by id; nothing changes",
        arguments: Takeover.allCases
    )
    func takeover_isRefused(takeover: Takeover) async throws {
        let stack = try await S3Kit.stack()
        let first = try await Self.prepare(takeover, in: stack)
        let (thief, key) = Self.thief(takeover)
        stack.clock.advance()
        let before = try await stack.dump()
        await #expect(throws: LedgerPersistenceError.duplicateIdentifier(key)) { try await stack.materialize(thief) }
        #expect(try await stack.dump() == before, "rows changed")
        // The same through a stored workout's materialisation and edit.
        let second = S3Kit.mixed(2)
        try await stack.materialize(second)
        let stored = try await stack.dump()
        await #expect(throws: LedgerPersistenceError.duplicateIdentifier(key)) { try await stack.materialize(thief) }
        if key.hasPrefix("logged_set") {
            await #expect(throws: LedgerPersistenceError.duplicateIdentifier(key)) {
                try await stack.workouts.updateSets(
                    workoutExerciseID: second.exercises[1].id,
                    sets: thief.exercises[1].sets
                )
            }
        }
        #expect(try await stack.dump() == stored, "rows changed")
        #expect(try await stack.workouts.workout(id: S3Kit.workoutID(1)) == first)
        // Both save again afterwards, each with its own ids.
        try await stack.materialize(S3Kit.mixed(1, endedAt: S3Kit.day(-1)))
        #expect(try await stack.workouts.recent(limit: 5) == [second, S3Kit.mixed(1, endedAt: S3Kit.day(-1))])
    }

    @Test("A workout may move its own set to another of its rows, and bring back a row and a set it dropped")
    func ownIDs_moveFreely() async throws {
        let stack = try await S3Kit.stack()
        let first = S3Kit.mixed(1)
        try await stack.materialize(first)
        var moved = first
        moved.exercises[1].sets.append(moved.exercises[0].sets.removeFirst())
        try await stack.materialize(moved)
        #expect(try await stack.workouts.workout(id: first.id) == moved)
        var smaller = moved
        smaller.exercises.removeFirst()
        try await stack.materialize(smaller)
        try await stack.materialize(first)
        #expect(try await stack.workouts.workout(id: first.id) == first)
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts([first]))
        #expect(try await S2Kit.count(stack.queue, "logged_set") == first.totalSets, "a set was stored twice")
    }

    /// Finding S3-1, after the F05 records follow-up (product decision #27): records are detected by the
    /// repository, never given, so a record can no longer name another workout (S3-1's two tests went with the
    /// `prs` argument). What stays to check: every stored record names the workout whose sets set it, and every
    /// `pr_count` counts that workout's live records.
    @Test("Every stored record names the workout whose sets set it, and each pr_count counts that workout's records")
    func records_nameTheirWorkout_andAreCounted() async throws {
        let stack = try await S3Kit.stack()
        let first = S3Kit.mixed(1, endedAt: S3Kit.day(-1))
        try await stack.materialize(S3Kit.baseline)
        try await stack.materialize(S3Kit.mixed(2))
        stack.clock.advance()
        try await stack.materialize(first) // stored late, before the second: it sets the records, the second ties
        #expect(try await stack.stats().personalRecords(exerciseID: S3Kit.bench) == S3Kit.mixedRecords(of: first))
        let owners = try await stack.texts("SELECT DISTINCT workout_id FROM personal_record WHERE deleted_at IS NULL")
        #expect(owners == [first.id.rawValue.uuidString])
        let counts = try await stack.texts("""
        SELECT workout.pr_count || ' counted, ' || COUNT(personal_record.id) || ' stored' FROM workout
        LEFT JOIN personal_record ON personal_record.workout_id = workout.id AND personal_record.deleted_at IS NULL
        WHERE workout.deleted_at IS NULL GROUP BY workout.id HAVING workout.pr_count != COUNT(personal_record.id)
        """)
        #expect(counts == [], "pr_count disagrees with the stored records")
    }
}
