import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBWorkoutRepository` and the tables a save reaches beside history's (F10 S3 criteria 1 to 4), at the
/// level of rows and statements, where the shared contract (`WorkoutRepositoryContract.linkedClauses`) cannot
/// look: one transaction and its order, which columns of which rows a program update writes, that a second
/// save writes no row at all, the rows a skipped update leaves alone, and a failure after the workout's rows
/// rolling all of it back.
@Suite("GRDBWorkoutRepository · program updates and the log", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutRepositoryLinkedTests {
    typealias Contract = WorkoutRepositoryContract

    /// Every row of the tables a save may write, with its stamps: history's four, the misses, the slots (with
    /// their exercise), the other program tables, and the log.
    static let everyRow = """
    SELECT 'workout ' || id || updated_at || quote(deleted_at) FROM workout
    UNION ALL SELECT 'exercise ' || id || updated_at || quote(deleted_at) FROM workout_exercise
    UNION ALL SELECT 'set ' || id || updated_at || quote(deleted_at) FROM logged_set
    UNION ALL SELECT 'record ' || id || updated_at || quote(deleted_at) FROM personal_record
    UNION ALL SELECT 'miss ' || id || updated_at || quote(deleted_at) FROM slot_miss
    UNION ALL SELECT 'slot ' || id || exercise_id || updated_at || quote(deleted_at) FROM slot
    UNION ALL SELECT 'day ' || id || updated_at || quote(deleted_at) FROM day_template
    UNION ALL SELECT 'week ' || id || updated_at || quote(deleted_at) FROM program_week
    UNION ALL SELECT 'program ' || id || is_active || updated_at || quote(deleted_at) FROM program
    UNION ALL SELECT 'event ' || workout_id || device_id || seq FROM workout_event
    ORDER BY 1
    """

    /// How many rows differ between two dumps, and the first that does: a failure prints this, not the dumps.
    static func difference(_ rows: [String], from before: [String]) -> String? {
        let changed = Set(rows).symmetricDifference(before).sorted()
        return changed.first.map { "\(changed.count) rows differ, the first: \($0.prefix(60))" }
    }

    /// The statements of a save that this suite places: the transaction's ends, the workout's row, the miss,
    /// the program update and the log's end.
    static let placed = [
        "BEGIN", "INSERT INTO workout ", "INSERT INTO slot_miss", "UPDATE slot SET", "DELETE FROM workout_event",
        "COMMIT"
    ]

    @Test("Criteria 1 and 4: the rows, the miss, the slot's exercise and the log's end are one transaction, in order")
    func save_isOneTransaction_inOrder() async throws {
        let scenario = try await Scenario()
        let statements = try await scenario.repositories.statements(startingWith: "") { try await scenario.save() }
        let kinds = statements.compactMap { statement in Self.placed.first { statement.hasPrefix($0) } }
        #expect(kinds == Self.placed)
        #expect(try await scenario.repositories.events.uncompactedWorkoutIDs() == [scenario.otherLog])
        #expect(try await scenario.repositories.count("SELECT COUNT(*) FROM workout_event") == 2)
    }

    @Test("Criterion 1: a program update writes one slot row's exercise and updated_at, and no other column or row")
    func programUpdate_writesTwoColumnsOfOneRow() async throws {
        let scenario = try await Scenario()
        let slot = ColumnCodec.text(scenario.swapped.id)
        let columns = """
        SELECT day_template_id || position || sets || reps || reps_hi || rpe_x2 || rest_seconds || progression
            || quote(start_load_e7g) || quote(step_e7g) || is_superset_with_previous || drop_sets || created_at
            || quote(deleted_at) FROM slot WHERE id = ?
        """
        let before = try await scenario.rows()
        let untouched = try await scenario.repositories.texts(columns, [slot])
        try await scenario.save()
        let exercise = ColumnCodec.text(scenario.replacement)
        #expect(try await scenario.slotsWritten(since: before) == [
            "slot \(slot)\(exercise)\(scenario.repositories.clock.timestamp)NULL"
        ])
        #expect(try await scenario.repositories.texts(columns, [slot]) == untouched)
        // The slot's two misses stay with it: a swap changes the exercise, not what was recorded for the slot.
        let misses = "SELECT COUNT(*) FROM slot_miss WHERE slot_id = ? AND deleted_at IS NULL AND updated_at < ?"
        #expect(try await scenario.repositories.count(misses, [slot, scenario.repositories.clock.timestamp]) == 2)
    }

    @Test("Criterion 3: a second save writes no row of any table, with the log gone or there again")
    func secondSave_writesNoRow() async throws {
        let scenario = try await Scenario()
        try await scenario.save()
        let saved = try await scenario.rows()
        scenario.repositories.clock.advance()
        let statements = try await scenario.repositories.statements(startingWith: "") { try await scenario.save() }
        #expect(statements.filter { $0.hasPrefix("INSERT") || $0.hasPrefix("UPDATE") } == [])
        #expect(try await Self.difference(scenario.rows(), from: saved) == nil)
        // The log is there again (a store that could not drop it with the first save): only its rows go.
        _ = try await scenario.repositories.events.append(Contract.log(of: scenario.workout.id, count: 3))
        scenario.repositories.clock.advance()
        try await scenario.save()
        #expect(try await Self.difference(scenario.rows(), from: saved) == nil)
    }
}

/// What is skipped, and what a failure rolls back.
extension WorkoutRepositoryLinkedTests {
    /// What makes a slot one the workout's own program no longer holds: each is a statement on the stored rows.
    static let estrangements = [
        "UPDATE slot SET deleted_at = 'gone' WHERE id = :slot",
        "UPDATE day_template SET deleted_at = 'gone' WHERE id = (SELECT day_template_id FROM slot WHERE id = :slot)",
        "UPDATE program SET deleted_at = 'gone' WHERE id = :program",
        "UPDATE day_template SET program_id = :other WHERE id = (SELECT day_template_id FROM slot WHERE id = :slot)"
    ]

    @Test(
        "Criterion 2: a slot that is deleted, under a deleted day or program, or another program's, is never written",
        arguments: estrangements
    )
    func estrangedSlot_isSkipped(by statement: String) async throws {
        let scenario = try await Scenario()
        try await scenario.repositories.execute(statement, [
            "slot": ColumnCodec.text(scenario.swapped.id),
            "program": ColumnCodec.text(scenario.program.id),
            "other": ColumnCodec.text(scenario.other.id)
        ])
        let before = try await scenario.rows()
        try await scenario.save()
        #expect(try await scenario.slotsWritten(since: before) == [])
        #expect(try await scenario.repositories.workouts.workout(id: scenario.workout.id) != nil)
        #expect(try await scenario.repositories.events.uncompactedWorkoutIDs() == [scenario.otherLog])
    }

    @Test("Criterion 2: a deleted program's slot, an exercise with no row and an ad-hoc workout's update are skipped")
    func whatCannotBeApplied_writesNoSlot() async throws {
        let scenario = try await Scenario()
        try await scenario.repositories.programs.delete(scenario.other.id)
        let before = try await scenario.rows()
        var stranger = Contract.workout(of: scenario.other, number: 1) // its program is deleted
        stranger.programUpdates = [scenario.other.days[0].slots[0].id: Contract.exercises[5].id]
        var unknown = Contract.workout(of: scenario.program, number: 2) // names an exercise that has no row
        unknown.programUpdates = [scenario.swapped.id: ExerciseID(EventBuilders.uuid(0x404))]
        var adHoc = Contract.workout(number: 3)
        adHoc.programUpdates = scenario.workout.programUpdates
        for workout in [stranger, unknown, adHoc] {
            try await scenario.repositories.history.materialize(workout)
        }
        #expect(try await scenario.slotsWritten(since: before) == [])
        #expect(try await scenario.repositories.workouts.recent(limit: 5).count == 3)
        // A soft-deleted exercise still has its row, which is what the slot's foreign key and a program save ask.
        try await scenario.repositories.execute(
            "UPDATE exercise SET deleted_at = 'gone' WHERE id = ?", [ColumnCodec.text(scenario.replacement)]
        )
        try await scenario.save()
        #expect(try await scenario.slotsWritten(since: before).count == 1)
    }

    /// A statement of the save that comes after the workout's rows: its miss, its program update, its log.
    static let lateStatements = ["INSERT ON slot_miss", "UPDATE OF exercise_id ON slot", "DELETE ON workout_event"]

    @Test(
        "Criterion 4: a save that fails after the workout's rows changes no row, no miss, no slot, and keeps the log",
        arguments: lateStatements
    )
    func lateFailure_rollsEverythingBack(failing statement: String) async throws {
        let scenario = try await Scenario()
        try await scenario.repositories.execute(
            "CREATE TRIGGER injected BEFORE \(statement) BEGIN SELECT RAISE(ABORT, 'injected failure'); END"
        )
        let before = try await scenario.rows()
        await #expect(throws: DatabaseError.self) { try await scenario.save() }
        #expect(try await Self.difference(scenario.rows(), from: before) == nil)
        #expect(try await scenario.repositories.events.envelopes(for: scenario.workout.id).count == 3)
        try await scenario.repositories.execute("DROP TRIGGER injected")
        try await scenario.save()
        #expect(try await scenario.repositories.workouts.workout(id: scenario.workout.id) != nil)
        #expect(try await scenario.repositories.events.uncompactedWorkoutIDs() == [scenario.otherLog])
    }

    @Test("Criterion 4: a refused workout drops no log and writes no slot, whatever the rows it reached")
    func refusedWorkout_rollsEverythingBack() async throws {
        let scenario = try await Scenario()
        let before = try await scenario.rows()
        var refused = scenario.workout
        refused.exercises[4].name = "Lat\u{0}Pulldown"
        await #expect(throws: LedgerPersistenceError.nulInText("workout_exercise.name")) {
            try await scenario.save(refused)
        }
        #expect(try await Self.difference(scenario.rows(), from: before) == nil)
    }
}

/// The stores these tests run on.
extension WorkoutRepositoryLinkedTests {
    /// Two stored programs (the first active), a workout of the first whose swap names `swapped`, a slot with
    /// two misses, a miss for another slot, and the logs of that workout and of another one. The clock has
    /// moved on since the programs were saved, so a row a save writes shows in its `updated_at`.
    struct Scenario {
        let repositories: Repositories
        let program: Program
        let other: Program
        let workout: WorkoutState
        let slots: [Slot]
        let otherLog = Seeders.workoutID(9)

        /// The slot the workout's swap names, and the exercise it asks for.
        var swapped: Slot {
            program.days[0].slots[1]
        }

        var replacement: ExerciseID {
            Contract.replacement(for: swapped)
        }

        init() async throws {
            repositories = try await Repositories.withProgramExercises()
            program = try ProgramRepositoryContract.program()
            other = try ProgramRepositoryContract.program(number: 1, isActive: false)
            try await repositories.programs.save(other)
            try await repositories.programs.save(program)
            var finished = Contract.workout(of: program)
            let slot = program.days[0].slots[1]
            finished.programUpdates = [slot.id: Contract.replacement(for: slot)]
            workout = finished
            var missed = program.days[1].slots[0]
            missed.misses = [2]
            slots = [missed]
            _ = try await repositories.events.append(
                Contract.log(of: workout.id, count: 3) + Contract.log(of: otherLog, count: 2)
            )
            repositories.clock.advance()
        }

        /// Saves the workout with its miss and its swap, dropping its log.
        func save(_ saved: WorkoutState? = nil) async throws {
            _ = try await repositories.workouts.materialize(saved ?? workout, slotUpdates: slots, droppingLog: true)
        }

        func rows() async throws -> [String] {
            try await repositories.texts(WorkoutRepositoryLinkedTests.everyRow)
        }

        /// The stored `slot` rows that are not in `before`, as "id exercise updated_at": the rows a save wrote.
        func slotsWritten(since before: [String]) async throws -> [String] {
            try await rows().filter { $0.hasPrefix("slot ") && !before.contains($0) }
        }
    }
}
