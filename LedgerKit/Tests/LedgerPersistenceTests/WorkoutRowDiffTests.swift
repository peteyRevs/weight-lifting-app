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
        try await repositories.history.materialize(workout)
        let first = repositories.clock.timestamp
        repositories.clock.advance()
        let edited = Contract.edited(workout)
        try await repositories.history.materialize(edited)
        let edit = repositories.clock.timestamp
        #expect(try await repositories.workouts.workout(id: workout.id) == edited)
        // Gone: the last exercise with its 3 sets, and a set of the first exercise.
        #expect(try await repositories.texts(Self.deletedCounts, ["stamp": edit]) == ["0 1 4 0"])
        // Written: the workout (name, totals, record count), two changed sets and the added one, plus the soft
        // deletes above, and four new records: the second exercise's 57.5 × 10 and the third's added 75 × 6 now
        // beat the earlier workout (product decision #27). The first exercise's two records stay as they were.
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": edit]) == ["1 1 7 4"])
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": first]) == ["0 4 13 2"])
        #expect(try await repositories.texts(Tests.liveCounts) == ["2 9 35 6 16"])
        let row = "SELECT pr_count || ' ' || created_at FROM workout WHERE id = ?"
        #expect(try await repositories.texts(row, [ColumnCodec.text(workout.id)]) == ["6 \(first)"])
    }

    @Test("updateSets computes the e1RMs, the workout's totals and its records again, and leaves other rows")
    func updateSets_recomputesE1RM_andTotals() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        try await repositories.history.materialize(workout)
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
        let totals = """
        SELECT volume_e7g_reps || ' ' || done_sets || ' ' || total_sets || ' ' || pr_count FROM workout WHERE id = ?
        """
        #expect(try await repositories.texts(totals, [ColumnCodec.text(workout.id)]) == [
            "\(edited.volume.e7gReps()) 16 18 2"
        ])
        // Written: the workout's totals, two changed sets, the soft delete of the removed one, and both records,
        // in their own rows: 200 × 3 now holds the best estimate and the best weight (product decision #27).
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": edit]) == ["1 0 3 2"])
        #expect(try await repositories.texts(Self.deletedCounts, ["stamp": edit]) == ["0 0 1 0"])
        #expect(try await repositories.texts(Self.updatedCounts, ["stamp": first]) == ["0 5 16 0"])
        let kinds = try await repositories.stats.personalRecords(exerciseID: workout.exercises[0].exerciseID)
        #expect(kinds.map(\.kind) == [.estimatedOneRepMax(heavy), .weightAtReps(.pounds(200), Reps(clamping: 3))])
    }

    @Test("updateSets with the sets it already has writes no row")
    func updateSets_unchanged_writesNoRow() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        try await repositories.history.materialize(workout)
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
        try await repositories.history.materialize(workout)
        let first = repositories.clock.timestamp
        repositories.clock.advance()
        let deletes = try await repositories.statements(startingWith: "UPDATE logged_set") {
            try await repositories.workouts.delete(id: workout.id)
        }
        let deleted = repositories.clock.timestamp
        #expect(try await repositories.texts(Self.deletedCounts, ["stamp": deleted]) == ["1 5 19 2"])
        #expect(try await repositories.texts(Tests.liveCounts) == ["1 5 19 0 16"]) // the earlier workout
        // One order on every launch: the sets by position, then id.
        let ordered = try await repositories.texts("""
        SELECT logged_set.id FROM logged_set JOIN workout_exercise ON workout_exercise.id = workout_exercise_id
        WHERE workout_id = ? ORDER BY logged_set.position, logged_set.id
        """, [ColumnCodec.text(workout.id)])
        #expect(deletes.count == 19)
        #expect(zip(deletes, ordered).allSatisfy { $0.hasSuffix("WHERE id = '\($1)'") })
        repositories.clock.advance()
        try await repositories.history.materialize(workout)
        #expect(try await repositories.workouts.workout(id: workout.id) == workout)
        #expect(try await repositories.texts(Tests.liveCounts) == ["2 10 38 2 16"])
        let created = "SELECT DISTINCT created_at FROM logged_set WHERE updated_at != created_at"
        #expect(try await repositories.texts(created) == [first])
    }
}

/// Compaction after materialisation, misses, a lone soft delete, and the derived ids of record rows.
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

    @Test("A workout row soft-deleted on its own is repaired by a rebuild, and delete clears rows under it (S3-2)")
    func loneSoftDeletedParent_hidesNoRows() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        try await repositories.history.materialize(workout)
        let id: StatementArguments = [ColumnCodec.text(workout.id)]
        try await repositories.execute("UPDATE workout SET deleted_at = 'then' WHERE id = ?", id)
        try await repositories.execute(
            "UPDATE workout_exercise SET deleted_at = 'then' WHERE position = 1 AND workout_id = ?",
            id
        )
        let edited = Contract.edited(workout)
        try await repositories.history.materialize(edited)
        #expect(try await repositories.workouts.workout(id: workout.id) == edited)
        #expect(try await repositories.texts(Tests.liveCounts) == ["2 9 35 6 16"]) // as in `rematerialize_diffsRows`
        try await repositories.execute("UPDATE workout SET deleted_at = 'then' WHERE id = ?", id)
        try await repositories.workouts.delete(id: workout.id)
        #expect(try await repositories.texts(Tests.liveCounts) == ["1 5 19 0 16"])
    }

    @Test("A record's row id is the version-5 UUID of its workout, exercise and kind: the same however it changes")
    func recordIDs_areDerived() async throws {
        let scenario = try await Tests.Scenario()
        let (repositories, workout) = (scenario.repositories, scenario.workout)
        try await scenario.materialize()
        func id(_ kind: String) -> String {
            let name = "personal_record \(ColumnCodec.text(workout.exercises[0].exerciseID)) \(kind)"
            return ColumnCodec.derivedID(named: name, in: workout.id.rawValue).uuidString
        }
        let read = { try await repositories.queue.read { database in
            try PersonalRecordRecord.fetchAll(database, sql: "SELECT * FROM personal_record ORDER BY kind")
        } }
        let stored = try await read()
        #expect(stored.map(\.rowID) == [id("estimatedOneRepMax"), id("weightAtReps")])
        #expect(stored.map(\.record) == scenario.records) // a record read from a row keeps its id (review N4)
        #expect(stored.first?.rowID.dropFirst(14).first == "5") // the version nibble
        // An edit to 200 × 3 changes both records' values: in their own rows, none added or deleted.
        var sets = workout.exercises[0].sets
        sets[0].weight = .pounds(200)
        sets[0].reps = Reps(clamping: 3)
        try await repositories.workouts.updateSets(workoutExerciseID: workout.exercises[0].id, sets: sets)
        let edited = try await read()
        #expect(edited.map(\.rowID) == stored.map(\.rowID))
        #expect(edited.map(\.record) != stored.map(\.record))
        #expect(try await repositories.count("SELECT COUNT(*) FROM personal_record WHERE deleted_at IS NULL") == 2)
        // RFC 9562's own example: the version-5 UUID of "www.example.com" in the DNS namespace.
        let dns = try #require(UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"))
        let example = ColumnCodec.derivedID(named: "www.example.com", in: dns)
        #expect(example.uuidString == "2ED6657D-E927-568B-95E1-2665A8AEA6A2")
    }
}
