import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S2 adversarial (G2): `observeWorkout(id:)` against writes and damage. A write that changes nothing, set taps
/// logged against the workout's own id and a settings save emit nothing; damage to another workout leaves the stream
/// running, while damage to its own row, exercise, set or record ends it (N10), before or after it is observed.
@Suite("Adversarial F13 S2 · observeWorkout against writes and damage", .tags(.persistence), .timeLimit(.minutes(2)))
struct WorkoutDetailDamageAdversarialTests {
    static func describe(_ value: RecordedWorkout??) -> String {
        WorkoutDetailObservationAdversarialTests.describe(value)
    }

    @Test("A write that changes nothing, a set tap logged for the workout itself and a settings save emit nothing")
    func writesThatChangeNothing_emitNothing() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1, endedAt: S3Kit.day(-1))
        try await stack.materialize(workout)
        let values = LibraryArrivals(stack.workouts.observeWorkout(id: workout.id))
        defer { values.cancel() }
        let first = await values.next(within: .seconds(5))
        #expect(first??.workout == workout)
        let events = GRDBWorkoutEventStore(stack.queue, now: { stack.clock.now })
        let settings = GRDBSettingsRepository(stack.queue)
        let writes: [(String, () async throws -> Void)] = [
            ("the same sets again", {
                try await stack.workouts.updateSets(
                    workoutExerciseID: workout.exercises[0].id,
                    sets: workout.exercises[0].sets
                )
            }),
            ("the same workout materialised again (a sync's resend)", { try await stack.materialize(workout) }),
            ("set taps logged against the workout's own id", {
                _ = try await events.append(EventBuilders.log(
                    from: [.restSkipped, .restSkipped],
                    workoutID: workout.id
                ))
            }),
            ("a settings save", { try await settings.save(.default) })
        ]
        for (what, write) in writes {
            stack.clock.advance()
            try await write()
            let value = await values.next(within: .milliseconds(200))
            #expect(value == nil, "a value after \(what): \(Self.describe(value))")
        }
        try await stack.workouts.delete(id: workout.id)
        let afterDelete = await values.next(within: .seconds(5))
        #expect(afterDelete == .some(nil), "the stream is alive: its delete emits nil")
    }

    // MARK: - Damage

    @Test("Damage to another workout leaves the stream running")
    func damageElsewhere_keepsTheStream() async throws {
        let stack = try await S3Kit.stack()
        let mine = S3Kit.workout(1, endedAt: S3Kit.day(-2), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5)])])
        let other = S3Kit.workout(2, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(105, 5)])])
        try await stack.materialize(mine)
        try await stack.materialize(other)
        let values = LibraryArrivals(stack.workouts.observeWorkout(id: mine.id))
        defer { values.cancel() }
        _ = await values.next(within: .seconds(5))
        let id = ColumnCodec.text(other.id)
        try await stack.damage("UPDATE workout SET started_at = 'soon' WHERE id = ?", [id])
        try await stack.damage("""
        UPDATE logged_set SET weight_e7g = 'heavy' WHERE workout_exercise_id IN
            (SELECT id FROM workout_exercise WHERE workout_id = ?)
        """, [id])
        try await stack.damage("UPDATE personal_record SET kind = 'fastest' WHERE workout_id = ?", [id])
        _ = await values.next(within: .milliseconds(200))
        try await stack.workouts.delete(id: mine.id)
        let afterDelete = await values.next(within: .seconds(5))
        #expect(afterDelete == .some(nil), "the stream did not end on another workout's damage")
    }

    static let ownDamage = [
        "UPDATE workout SET started_at = 'soon' WHERE id = ?",
        "UPDATE workout_exercise SET equipment = 'trebuchet' WHERE workout_id = ?",
        """
        UPDATE logged_set SET weight_e7g = 'heavy' WHERE workout_exercise_id IN
            (SELECT id FROM workout_exercise WHERE workout_id = ?)
        """,
        "UPDATE personal_record SET kind = 'fastest' WHERE workout_id = ?"
    ]

    @Test("Damage to the workout's own row, exercise, set or record ends its stream (N10)", arguments: ownDamage)
    func ownDamage_endsTheStream(_ damage: String) async throws {
        let stack = try await S3Kit.stack()
        let baseline = S3Kit.workout(2, endedAt: S3Kit.day(-2), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(95, 5)])])
        let mine = S3Kit.workout(1, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5)])])
        try await stack.materialize(baseline)
        try await stack.materialize(mine)
        let records = try await stack.texts(
            "SELECT kind FROM personal_record WHERE workout_id = ?",
            [ColumnCodec.text(mine.id)]
        )
        try #require(!records.isEmpty, "100 over 95 holds records to damage")
        let values = LibraryArrivals(stack.workouts.observeWorkout(id: mine.id))
        defer { values.cancel() }
        _ = await values.next(within: .seconds(5))
        try await stack.damage(damage, [ColumnCodec.text(mine.id)])
        let after = await values.next(within: .seconds(5))
        #expect(after == nil, "\(damage): \(Self.describe(after))")
        // Ended, not merely quiet: a later delete emits nothing either. N10's "You can still delete it" holds: the
        // delete succeeds and the list loses the workout (review S2-R1-5).
        try await stack.workouts.delete(id: mine.id)
        let afterDelete = await values.next(within: .milliseconds(200))
        #expect(afterDelete == nil)
        let listed = try await stack.workouts.historyEntries()
        #expect(!listed.contains { $0.id == mine.id }, "\(damage): the deleted workout leaves the list")
    }

    /// Review S2-R1-5 (g2): the observation reads `personal_record` too. A record of the workout that changes while
    /// the workout's own rows and its count stay as they are (here its `previous`, written alone) emits the new value.
    @Test("A record of the workout changed alone, its count the same, emits the workout with the new record")
    func recordChangedAlone_emits() async throws {
        let stack = try await S3Kit.stack()
        let baseline = S3Kit.workout(2, endedAt: S3Kit.day(-2), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(95, 5)])])
        let mine = S3Kit.workout(1, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5)])])
        try await stack.materialize(baseline)
        try await stack.materialize(mine)
        let values = LibraryArrivals(stack.workouts.observeWorkout(id: mine.id))
        defer { values.cancel() }
        let first = try #require(await values.next(within: .seconds(5)) ?? nil)
        try #require(!first.records.isEmpty, "100 over 95 holds records")
        try await stack.damage(
            "UPDATE personal_record SET previous_weight_e7g = previous_weight_e7g - 10000000 WHERE workout_id = ?",
            [ColumnCodec.text(mine.id)]
        )
        let after = try #require(await values.next(within: .seconds(5)) ?? nil, "the record's change emits")
        #expect(after.records.count == first.records.count)
        let changed = after.records != first.records && after.workout == first.workout
        #expect(changed, "only the records moved")
    }

    @Test("A workout damaged before it is observed ends the stream at once, without a value")
    func damagedBeforeObserving_endsWithoutAValue() async throws {
        let stack = try await S3Kit.stack()
        let mine = S3Kit.workout(1, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5)])])
        try await stack.materialize(mine)
        try await stack.damage(
            "UPDATE workout_exercise SET equipment = 'trebuchet' WHERE workout_id = ?",
            [ColumnCodec.text(mine.id)]
        )
        let values = LibraryArrivals(stack.workouts.observeWorkout(id: mine.id))
        defer { values.cancel() }
        let first = await values.next(within: .seconds(5))
        #expect(first == nil)
        let listed = try await stack.workouts.historyEntries()
        #expect(listed.map(\.id) == [mine.id], "the list still shows it (A5), so its detail is reachable and says N10")
    }
}
