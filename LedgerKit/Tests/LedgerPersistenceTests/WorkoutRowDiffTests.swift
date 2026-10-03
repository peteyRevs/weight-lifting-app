import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// How `GRDBWorkoutRepository` writes a stored workout again: the idempotent upsert of `materialize`, the
/// diff of `updateSets`, ADR-002's soft deletes, and compaction after materialisation (criterion 8).
@Suite("GRDBWorkoutRepository · stored rows", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutRowDiffTests {
    typealias Contract = WorkoutRepositoryContract
    typealias Tests = WorkoutRepositoryTests

    /// How many rows of each history table carry `:stamp` as their `updated_at`: workout, exercise, set, record.
    static let updatedCounts = """
    SELECT (SELECT COUNT(*) FROM workout WHERE updated_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM workout_exercise WHERE updated_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM logged_set WHERE updated_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM personal_record WHERE updated_at = :stamp)
    """

    /// The same, for rows soft-deleted at `:stamp`.
    static let deletedCounts = """
    SELECT (SELECT COUNT(*) FROM workout WHERE deleted_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM workout_exercise WHERE deleted_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM logged_set WHERE deleted_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM personal_record WHERE deleted_at = :stamp)
    """

    @Test("Materialising the same workout again writes no row: every updated_at stays")
    func materializeTwice_writesNoRow() async throws {
        let scenario = try await Tests.Scenario()
        let repositories = scenario.repositories
        try await scenario.materialize()
        let before = try await repositories.texts(Tests.everyRow)
        repositories.clock.advance()
        let writes = try await repositories.statements(startingWith: "") {
            try await scenario.materialize()
        }.filter { $0.hasPrefix("INSERT") || $0.hasPrefix("UPDATE") }
        #expect(writes.isEmpty)
        #expect(try await repositories.texts(Tests.everyRow) == before)
    }

    @Test("A changed workout rewrites only what changed: other rows keep updated_at, removed ones are soft-deleted")
    func rematerialize_diffsRows() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        let records = scenario.records
        try await repositories.history.materialize(workout, prs: records)
        let first = repositories.clock.timestamp
        repositories.clock.advance()
        let edited = Contract.edited(workout)
        try await repositories.history.materialize(edited, prs: [records[1]])
        let edit = repositories.clock.timestamp
        #expect(try await repositories.workouts.workout(id: workout.id) == edited)
        // Gone: the last exercise with its 3 sets, a set of the first exercise, and the second record.
        #expect(try await repositories.texts(Self.deletedCounts, ["stamp": edit]) == ["0 1 4 1"])
        // Written: the workout (name, totals, record count), two changed sets and the added one, and the
        // first record, which now holds what the second did; plus the five soft deletes above.
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": edit]) == ["1 1 7 2"])
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": first]) == ["0 4 13 0"])
        #expect(try await repositories.texts(Tests.liveCounts) == ["1 4 16 1 16"])
        #expect(try await repositories.texts("SELECT pr_count || ' ' || created_at FROM workout") == ["1 \(first)"])
    }

    @Test("updateSets computes the e1RMs and the workout's totals again, and leaves its records and other rows")
    func updateSets_recomputesE1RM_andTotals() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        let records = scenario.records
        try await repositories.history.materialize(workout, prs: records)
        let first = repositories.clock.timestamp
        repositories.clock.advance()
        var edited = workout
        edited.exercises[0].sets.removeLast()
        edited.exercises[0].sets[0].weight = .pounds(200)
        edited.exercises[0].sets[0].reps = Reps(clamping: 3)
        edited.exercises[0].sets[1].doneAt = nil
        let bench = workout.exercises[0].id
        try await repositories.workouts.updateSets(workoutExerciseID: bench, sets: edited.exercises[0].sets)
        let edit = repositories.clock.timestamp
        #expect(try await repositories.workouts.workout(id: workout.id) == edited)
        let estimates = try await repositories.texts(
            """
            SELECT quote(e1rm_e7g) FROM logged_set WHERE workout_exercise_id = ? AND deleted_at IS NULL
            ORDER BY position
            """,
            [ColumnCodec.text(bench)]
        )
        let heavy = try #require(OneRepMax.brzycki(weight: .pounds(200), reps: Reps(clamping: 3)))
        #expect(try estimates == [String(heavy.e7g()), "NULL", "944040000000", "944040000000"])
        let totals = "SELECT volume_e7g_reps || ' ' || done_sets || ' ' || total_sets || ' ' || pr_count FROM workout"
        #expect(try await repositories.texts(totals) == ["\(edited.volume.e7gReps()) 16 18 2"])
        // Written: the workout's totals, two changed sets and the soft delete of the removed one.
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": edit]) == ["1 0 3 0"])
        #expect(try await repositories.texts(Self.deletedCounts, ["stamp": edit]) == ["0 0 1 0"])
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": first]) == ["0 5 16 2"])
        #expect(try await repositories.stats.personalRecords(exerciseID: workout.exercises[0].exerciseID) == records)
    }

    @Test("updateSets with the sets it already has writes no row")
    func updateSets_unchanged_writesNoRow() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        let records = scenario.records
        try await repositories.history.materialize(workout, prs: records)
        let before = try await repositories.texts(Tests.everyRow)
        repositories.clock.advance()
        try await repositories.workouts.updateSets(
            workoutExerciseID: workout.exercises[1].id,
            sets: workout.exercises[1].sets
        )
        #expect(try await repositories.texts(Tests.everyRow) == before)
    }

    @Test("delete soft-deletes the workout and every row under it, in stored order; a new materialise revives them")
    func delete_cascades_softly() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        let records = scenario.records
        try await repositories.history.materialize(workout, prs: records)
        let first = repositories.clock.timestamp
        repositories.clock.advance()
        let deletes = try await repositories.statements(startingWith: "UPDATE logged_set") {
            try await repositories.workouts.delete(id: workout.id)
        }
        let deleted = repositories.clock.timestamp
        #expect(try await repositories.texts(Self.deletedCounts, ["stamp": deleted]) == ["1 5 19 2"])
        #expect(try await repositories.texts(Tests.liveCounts) == ["0 0 0 0 16"])
        // One order on every launch: the sets by position, then id.
        let ordered = try await repositories.texts("SELECT id FROM logged_set ORDER BY position, id")
        #expect(deletes.count == 19)
        #expect(zip(deletes, ordered).allSatisfy { $0.hasSuffix("WHERE id = '\($1)'") })
        repositories.clock.advance()
        try await repositories.history.materialize(workout, prs: records)
        #expect(try await repositories.workouts.workout(id: workout.id) == workout)
        #expect(try await repositories.texts(Tests.liveCounts) == ["1 5 19 2 16"])
        #expect(try await repositories.texts("SELECT DISTINCT created_at FROM logged_set") == [first])
    }
}

/// Compaction after materialisation, and the derived ids of record rows.
extension WorkoutRowDiffTests {
    @Test("Criterion 8: a log is compacted after its workout is materialised; the workout stays, the events go")
    func materializeThenCompact_keepsTheWorkout() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let store = GRDBWorkoutEventStore(repositories.queue, now: repositories.clock.now)
        let workout = Contract.workout()
        let other = WorkoutEventStoreContract.other
        let log = EventBuilders.log(
            from: [.restSkipped, .finished(endedAt: EventBuilders.start)],
            workoutID: workout.id
        )
        _ = try await store.append(log + [WorkoutEventStoreContract.start(other)])
        try await repositories.history.materialize(workout)
        try await store.compact(workout: workout.id)
        #expect(try await store.uncompactedWorkoutIDs() == [other])
        #expect(try await store.envelopes(for: workout.id).isEmpty)
        #expect(try await repositories.workouts.recent(limit: 5) == [workout])
        try await repositories.history.materialize(workout) // a late rebuild after compaction is still an upsert
        #expect(try await repositories.texts(Tests.liveCounts) == ["1 5 19 0 0"])
    }

    @Test("The misses of a slot the program dropped, or of one never stored, are not written; the workout is stored")
    func misses_ofASlotNotStored_areSkipped() async throws {
        let scenario = try await Tests.Scenario()
        let repositories = scenario.repositories
        var program = try ProgramRepositoryContract.program()
        var dropped = program.days[3].slots.removeLast()
        try await repositories.programs.save(program)
        dropped.misses = [1, 2, 3]
        var unknown = try Seeders.slot(77, day: 0, position: 0, last: false, Contract.exercises.map(\.id))
        unknown.misses = [4]
        let missRows = "SELECT COUNT(*) FROM slot_miss WHERE deleted_at IS NULL"
        let before = try await repositories.count(missRows)
        try await repositories.history.materialize(scenario.workout, slotUpdates: [dropped, unknown] + scenario.slots)
        #expect(try await repositories.count(missRows) == before + 1) // the stored slot's one miss
        #expect(try await repositories.workouts.workout(id: scenario.workout.id) == scenario.workout)
    }

    @Test("A record that names another workout is refused, naming that workout; nothing is written (S3-1)")
    func recordOfAnotherWorkout_isRefused() async throws {
        let scenario = try await Tests.Scenario()
        let repositories = scenario.repositories
        try await repositories.history.materialize(scenario.workout, prs: scenario.records)
        let before = try await repositories.texts(Tests.everyRow)
        repositories.clock.advance()
        let other = Contract.workout(number: 1, endedAt: EventBuilders.start.addingTimeInterval(3600))
        let own = Tests.records(of: other)[0]
        let stored = ColumnCodec.text(scenario.workout.id)
        await #expect(throws: LedgerPersistenceError.duplicateIdentifier("personal_record of workout \(stored)")) {
            try await repositories.history.materialize(other, prs: [own, scenario.records[1]])
        }
        #expect(try await repositories.texts(Tests.everyRow) == before)
        // A record naming a workout that is not stored is refused the same way, before the foreign key is.
        let unknown = Tests.records(of: Contract.workout(number: 9))[0]
        let absent = ColumnCodec.text(Seeders.workoutID(9))
        await #expect(throws: LedgerPersistenceError.duplicateIdentifier("personal_record of workout \(absent)")) {
            try await repositories.history.materialize(other, prs: [unknown])
        }
        #expect(try await repositories.texts(Tests.everyRow) == before)
    }

    @Test("A workout row soft-deleted on its own is repaired by a rebuild, and delete clears rows under it (S3-2)")
    func loneSoftDeletedParent_hidesNoRows() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        try await repositories.history.materialize(workout, prs: scenario.records)
        try await repositories.execute("UPDATE workout SET deleted_at = 'then'")
        try await repositories.execute("UPDATE workout_exercise SET deleted_at = 'then' WHERE position = 1")
        let edited = Contract.edited(workout)
        try await repositories.history.materialize(edited, prs: [scenario.records[0]])
        #expect(try await repositories.workouts.workout(id: workout.id) == edited)
        #expect(try await repositories.texts(Tests.liveCounts) == ["1 4 16 1 16"])
        try await repositories.execute("UPDATE workout SET deleted_at = 'then'")
        try await repositories.workouts.delete(id: workout.id)
        #expect(try await repositories.texts(Tests.liveCounts) == ["0 0 0 0 16"])
    }

    @Test("A record's row id is the version-5 UUID of its place in its workout: the same on every materialise")
    func recordIDs_areDerived() async throws {
        let workout = Contract.workout()
        let records = Tests.records(of: workout)
        let first = PersonalRecordRecord(records[0], position: 0).rowID
        #expect(first == PersonalRecordRecord(records[1], position: 0).rowID)
        #expect(first != PersonalRecordRecord(records[0], position: 1).rowID)
        let elsewhere = PersonalRecord(
            exerciseID: records[0].exerciseID,
            kind: records[0].kind,
            previous: nil,
            achievedAt: records[0].achievedAt,
            workoutID: Seeders.workoutID(9)
        )
        #expect(first != PersonalRecordRecord(elsewhere, position: 0).rowID)
        #expect(first.dropFirst(14).first == "5") // the version nibble
        // A record read from a row keeps the row's own id, whatever its place was (review N4).
        let repositories = try await Repositories.withProgramExercises()
        try await repositories.history.materialize(workout, prs: records)
        let stored = try await repositories.queue.read { database in
            try PersonalRecordRecord.fetchAll(database, sql: "SELECT * FROM personal_record ORDER BY kind")
        }
        #expect(stored.map(\.rowID) == [first, PersonalRecordRecord(records[1], position: 1).rowID])
        #expect(stored.map(\.record) == records)
        // RFC 9562's own example: the version-5 UUID of "www.example.com" in the DNS namespace.
        let dns = try #require(UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"))
        let example = ColumnCodec.derivedID(named: "www.example.com", in: dns)
        #expect(example.uuidString == "2ED6657D-E927-568B-95E1-2665A8AEA6A2")
    }
}
