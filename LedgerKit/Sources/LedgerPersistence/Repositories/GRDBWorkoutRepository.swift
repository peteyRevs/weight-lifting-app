import Foundation
import GRDB
import LedgerDomain
import os

/// `WorkoutRepository` over `workout`, `workout_exercise`, `logged_set` and `personal_record` (`WorkoutRows`):
/// the finished workouts. Deleted rows (`deleted_at`) are never read.
///
/// A workout's date, for ordering and for ranges, is when it started (`started_at`; product decision #26).
///
/// The personal records are derived (product decision #27): every write detects them again, in its own
/// transaction, for the exercises it touched from the workout it changed onward (`RecordReplay`), so they always
/// equal `PersonalRecords.detect` replayed over history.
///
/// A save reaches three tables that are not history's, in its own transaction, because what they hold is part
/// of the same fact as the workout: a slot's misses (`slot_miss`) and its exercise (`slot.exercise_id`), and,
/// when the caller asks, the workout's event log (`workout_event`), which the save makes obsolete.
public struct GRDBWorkoutRepository: WorkoutRepository {
    let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - queue: the database. A save that drops a log drops it from this queue's `workout_event` and answers
    ///     for no other: the event store a host is given beside this repository must be over the same queue,
    ///     as `LedgerStores` builds them. A host looks in its own event store all the same.
    ///   - now: the clock for `created_at` and `updated_at`; the composition root passes the injected date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// Stores the finished `workout` in one write transaction (rule 31): its row, its exercises and their sets
    /// (each done set of at most 12 reps with its Brzycki e1RM), its personal records, the misses of
    /// `slotUpdates` (rule 13), the program changes of `workout.programUpdates` (decision #13) and, when
    /// `droppingLog`, the end of its log. Any failure leaves the database as it was.
    ///
    /// It is an upsert keyed by the workout's id, so materialising again is safe (ADR-004: a rebuild emits
    /// `.materialize` again when a late envelope changes a finished log). Rows that did not change are left
    /// alone, rows the workout no longer has are soft-deleted, and a deleted workout comes back.
    ///
    /// - The stored totals (volume, done and total sets) are computed from `workout`'s sets.
    /// - The records of every exercise the workout performs, or performed before this write, are detected
    ///   again from the workout's place in history onward (product decision #27): a workout stored late, before
    ///   others, changes theirs too.
    /// - Of each slot in `slotUpdates`, only `misses` is written, and it replaces the slot's stored misses
    ///   whole. So the caller builds each slot from the program as it is stored now: a copy taken when the
    ///   workout started, or the slots of an older workout materialised again, would clear misses recorded
    ///   since. A slot that is not stored, or is deleted (the program was edited or deleted during the
    ///   workout), is logged and skipped: the workout is still stored.
    /// - Each entry of `workout.programUpdates` sets one slot's exercise (`writeProgramUpdates`), or is logged
    ///   and skipped. Like the misses it is written by every materialisation: an older workout stored again
    ///   with its entries sets a slot back that was changed since.
    /// - With `droppingLog`, every row of the workout's log in `workout_event` is deleted, last
    ///   (`GRDBWorkoutEventStore.deleteLog(of:in:)`, the statement `compact(workout:)` runs).
    ///
    /// The writes run in that order, and every refusal below is thrown before the misses are written, by the
    /// workout's place in history, its rows or its records: what follows them never refuses, it skips. So a
    /// refused workout has changed no slot and dropped no log even before the rollback, and whatever fails
    /// later (a full disk) rolls all of it back.
    ///
    /// Returns `droppingLog`: this repository holds the log, in the `workout_event` table of its own queue, and
    /// has dropped it there when asked. It cannot tell whether the caller's event store is over that queue.
    ///
    /// Throws `notFinished` unless `workout` is `.finished` with an `endedAt`; `duplicateIdentifier` for two
    /// exercises or two sets sharing an id, or an exercise or set id that another stored workout holds (live or
    /// deleted); `nulInText` for a name or tag holding U+0000; `inexactWeight` for a weight that is not a
    /// whole number of 10⁻⁷ g; and `nonFiniteDate` for a date that is not finite. A workout the record replay
    /// cannot read is left out of it and logged; it never fails the write.
    public func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog: Bool) async throws -> Bool {
        guard workout.phase == .finished, workout.endedAt != nil else {
            throw LedgerPersistenceError.notFinished("workout \(ColumnCodec.text(workout.id))")
        }
        let rows = WorkoutRows(workout)
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            var scope = try RecordReplay.Scope(ofStored: workout.id, in: database)
            try scope.include(workout)
            try rows.write(database, at: timestamp)
            try RecordReplay.redetect(scope, in: database, at: timestamp)
            try Self.writeMisses(of: slotUpdates, in: database, at: timestamp)
            try Self.writeProgramUpdates(of: workout, in: database, at: timestamp)
            if droppingLog {
                try GRDBWorkoutEventStore.deleteLog(of: workout.id, in: database)
            }
        }
        return droppingLog
    }

    /// The workout `id`, or `nil`. Its live-only fields are reset (`WorkoutRecord`). A workout this app cannot
    /// read throws `LedgerPersistenceError`.
    public func workout(id: WorkoutID) async throws -> WorkoutState? {
        try await queue.read { database in try WorkoutRows.fetch(.one(id), in: database, strict: true).first }
    }

    /// The `limit` workouts that started last, newest first; none when `limit` is not positive. A workout this
    /// app cannot read is logged and left out, and stays stored.
    public func recent(limit: Int) async throws -> [WorkoutState] {
        try await queue.read { database in try Self.fetchRecent(limit, in: database) }
    }

    /// The workouts that started in `range`, newest first. A workout this app cannot read is logged and left
    /// out, and stays stored.
    public func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
        try await queue.read { database in try WorkoutRows.fetch(.started(in: range), in: database, strict: false) }
    }

    /// Makes `sets` the sets of the stored exercise `workoutExerciseID`, in one write transaction: its other
    /// set rows are soft-deleted, each set's e1RM is computed again, and so are the workout's totals. Rows
    /// that did not change keep their `updated_at`.
    ///
    /// The exercise's personal records are detected again, in the same transaction, from this workout onward
    /// (product decision #27): correcting a typo removes the record it made, and gives a later workout the
    /// record it then deserves.
    ///
    /// Throws `missingRow` when no live workout has the exercise; `duplicateIdentifier` for a set id used
    /// twice in the workout, or held by another workout (live or deleted); and what reading the workout throws
    /// when it is damaged. A later workout the replay cannot read is left out and logged.
    public func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
        let timestamp = ColumnCodec.timestamp(now())
        let key = ColumnCodec.text(workoutExerciseID)
        try await queue.write { database in
            let owner = try String.fetchOne(
                database,
                sql: """
                SELECT workout.id FROM workout JOIN workout_exercise ON workout_exercise.workout_id = workout.id
                WHERE workout_exercise.id = ? AND workout_exercise.deleted_at IS NULL AND workout.deleted_at IS NULL
                """,
                arguments: [key]
            )
            guard let owner,
                  var workout = try WorkoutRows.fetch(.one(ColumnCodec.identifier(owner)), in: database, strict: true)
                  .first,
                  let index = workout.exercises.firstIndex(where: { $0.id == workoutExerciseID })
            else {
                throw LedgerPersistenceError.missingRow("workout_exercise \(key)")
            }
            workout.exercises[index].sets = sets
            let scope = try RecordReplay.Scope(editing: workout.exercises[index].exerciseID, of: workout)
            try WorkoutRows(workout).write(database, at: timestamp)
            try RecordReplay.redetect(scope, in: database, at: timestamp)
        }
    }

    /// Soft-deletes the workout, its exercises, sets and personal records in one transaction, and detects the
    /// records of its exercises again in the workouts after it (product decision #27); materialising it again
    /// brings them back. Deleting a workout that is not stored does nothing. The misses it recorded stay: they
    /// belong to the program.
    public func delete(id: WorkoutID) async throws {
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            let scope = try RecordReplay.Scope(ofStored: id, in: database)
            try WorkoutRows(deleting: id).write(database, at: timestamp)
            try RecordReplay.redetect(scope, in: database, at: timestamp)
        }
    }

    /// `recent(limit:)` now, then after every change that alters it.
    public func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        Self.recentObservation(limit: limit).stream(in: queue)
    }

    /// `observeRecent(limit:)`'s observation: `recent(limit:)`, emitted only when it differs from the last
    /// value.
    static func recentObservation(limit: Int) -> DistinctObservation<[WorkoutState]> {
        ValueObservation.tracking { database in try fetchRecent(limit, in: database) }.removeDuplicates()
    }

    private static func fetchRecent(_ limit: Int, in database: Database) throws -> [WorkoutState] {
        try WorkoutRows.fetch(.recent(limit: limit), in: database, strict: false)
    }

    /// Makes each slot's stored misses its `misses` (rule 13), in the order given, through the diff a program
    /// save uses: a miss that stays keeps its row, a new one is inserted and a cleared one soft-deleted.
    private static func writeMisses(of slots: [Slot], in database: Database, at timestamp: String) throws {
        for slot in slots {
            let key = ColumnCodec.text(slot.id)
            let isStored = try Int.fetchOne(
                database,
                sql: "SELECT 1 FROM slot WHERE id = ? AND deleted_at IS NULL",
                arguments: [key]
            ) != nil
            guard isStored else {
                Logger.persistence.notice("Skipped the misses of slot \(key, privacy: .public), which is not stored")
                continue
            }
            let stored = try Row.fetchAll(
                database,
                sql: "SELECT * FROM slot_miss WHERE slot_id = ? AND deleted_at IS NULL ORDER BY week_index, id",
                arguments: [key]
            )
            let misses = slot.misses.sorted().map { SlotMissRecord(slotID: slot.id, weekIndex: $0) }
            try SlotMissRecord.write(misses, over: stored, in: database, at: timestamp)
        }
    }

    /// Sets the exercise of each slot `workout.programUpdates` names (decision #13), in slot-id order, and
    /// nothing else of the slot: its numbers and its misses stay.
    ///
    /// An entry is applied only to a live slot, under a live day, of the workout's own live program, so a
    /// workout of one program never rewrites another's (the takeover class of F05 review B1), and only when
    /// its exercise has a row, as the slot's foreign key and a program save require
    /// (`ProgramRows.holdsExercise(_:in:)`, the one rule for both). Any other entry is logged and skipped: the
    /// program was edited or deleted during the workout, and the workout is still stored. A slot that already
    /// holds the exercise is left alone, so a second materialisation runs no statement that writes.
    private static func writeProgramUpdates(
        of workout: WorkoutState,
        in database: Database,
        at timestamp: String
    ) throws {
        guard !workout.programUpdates.isEmpty else {
            return
        }
        guard let program = workout.source.map({ ColumnCodec.text($0.programID) }) else {
            Logger.persistence.notice("Program updates of an ad-hoc workout skipped: it has no program")
            return
        }
        let updates = workout.programUpdates
            .map { (slot: ColumnCodec.text($0.key), exercise: ColumnCodec.text($0.value)) }
            .sorted { $0.slot < $1.slot }
        for (slot, exercise) in updates {
            // Whether the workout's own slot holds the exercise already; no row when the slot is not its own.
            let ownSlot = """
            SELECT slot.exercise_id IS ? FROM slot
            JOIN day_template ON day_template.id = slot.day_template_id
            JOIN program ON program.id = day_template.program_id
            WHERE slot.id = ? AND program.id = ?
                AND slot.deleted_at IS NULL AND day_template.deleted_at IS NULL AND program.deleted_at IS NULL
            """
            guard let isHeld = try Bool.fetchOne(database, sql: ownSlot, arguments: [exercise, slot, program]) else {
                Logger.persistence.notice(
                    "Program update of slot \(slot, privacy: .public) skipped: the workout's program has no such slot"
                )
                continue
            }
            guard !isHeld else {
                continue
            }
            guard try ProgramRows.holdsExercise(exercise, in: database) else {
                Logger.persistence.notice(
                    "Program update of slot \(slot, privacy: .public) skipped: its exercise is not stored"
                )
                continue
            }
            try database.execute(
                sql: "UPDATE slot SET exercise_id = ?, updated_at = ? WHERE id = ?",
                arguments: [exercise, timestamp, slot]
            )
        }
    }
}
