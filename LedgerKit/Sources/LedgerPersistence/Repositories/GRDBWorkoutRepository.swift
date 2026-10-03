import Foundation
import GRDB
import LedgerDomain
import os

/// `WorkoutRepository` over `workout`, `workout_exercise`, `logged_set` and `personal_record` (`WorkoutRows`):
/// the finished workouts. Deleted rows (`deleted_at`) are never read.
///
/// A workout's date, for ordering and for ranges, is when it started (`started_at`; product decision #26).
public struct GRDBWorkoutRepository: WorkoutRepository {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock for `created_at` and `updated_at`; the composition root passes the injected
    ///   date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// Stores the finished `workout` in one write transaction (rule 31): its row, its exercises and their sets
    /// (each done set of at most 12 reps with its Brzycki e1RM), `prs` as its personal records, and the misses
    /// of `slotUpdates` (rule 13). Any failure leaves the database as it was.
    ///
    /// It is an upsert keyed by the workout's id, so materialising again is safe (ADR-004: a rebuild emits
    /// `.materialize` again when a late envelope changes a finished log). Rows that did not change are left
    /// alone, rows the workout no longer has are soft-deleted, and a deleted workout comes back.
    ///
    /// - The stored totals (volume, done and total sets) are computed from `workout`'s sets, and the record
    ///   count is `prs.count`: `summary` is `WorkoutEngine.summary(workout, prs: prs)`, so it holds nothing
    ///   else to store.
    /// - Of each slot in `slotUpdates`, only `misses` is written, and it replaces the slot's stored misses
    ///   whole. So the caller builds each slot from the program as it is stored now: a copy taken when the
    ///   workout started, or the slots of an older workout materialised again, would clear misses recorded
    ///   since. A slot that is not stored, or is deleted (the program was edited or deleted during the
    ///   workout), is logged and skipped: the workout is still stored.
    /// - `workout.programUpdates` is not applied here; F10 decides where a swap reaches the program.
    ///
    /// Throws `notFinished` unless `workout` is `.finished` with an `endedAt`; `duplicateIdentifier` for two
    /// exercises or two sets sharing an id, an exercise or set id that another stored workout holds (live or
    /// deleted), or a record in `prs` that names another workout; `nulInText` for a name or tag holding U+0000;
    /// `inexactWeight` for a weight that is not a
    /// whole number of 10⁻⁷ g; and `nonFiniteDate` for a date that is not finite.
    public func materialize(
        _ workout: WorkoutState,
        summary _: WorkoutSummary,
        prs: [PersonalRecord],
        slotUpdates: [Slot]
    ) async throws {
        guard workout.phase == .finished, workout.endedAt != nil else {
            throw LedgerPersistenceError.notFinished("workout \(ColumnCodec.text(workout.id))")
        }
        let rows = WorkoutRows(workout, records: prs)
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            try rows.write(database, at: timestamp)
            try Self.writeMisses(of: slotUpdates, in: database, at: timestamp)
        }
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
    /// The workout's personal records and its record count are left as they are, so after an edit they can be
    /// stale: a record may remain that no stored set supports, and an edit that deserves one creates none.
    /// Product decision #27 has an edit re-check the records inside this write, against the bests as they
    /// stood before the workout; that is the F05 follow-up before F07, not yet built.
    ///
    /// Throws `missingRow` when no live workout has the exercise; `duplicateIdentifier` for a set id used
    /// twice in the workout, or held by another workout (live or deleted); and what reading the workout throws
    /// when it is damaged.
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
            try WorkoutRows(workout, records: nil).write(database, at: timestamp)
        }
    }

    /// Soft-deletes the workout, its exercises, sets and personal records in one transaction; materialising it
    /// again brings them back. Deleting a workout that is not stored does nothing. The misses it recorded
    /// stay: they belong to the program.
    public func delete(id: WorkoutID) async throws {
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in try WorkoutRows(deleting: id).write(database, at: timestamp) }
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
}
