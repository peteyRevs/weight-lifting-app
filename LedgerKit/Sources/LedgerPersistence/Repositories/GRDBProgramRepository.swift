import Foundation
import GRDB
import LedgerDomain

/// `ProgramRepository` over `program`, `program_week`, `day_template`, `slot` and `slot_miss` (`ProgramRows`).
/// At most one live program is active. Deleted rows (`deleted_at`) are never read.
public struct GRDBProgramRepository: ProgramRepository {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock for `created_at` and `updated_at`; the composition root passes the injected
    ///   date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// The active program, or `nil`. Stored values are validated as on construction, so a damaged or
    /// out-of-range row throws (`LedgerPersistenceError`, `SlotValidationError`, `ProgramValidationError`)
    /// rather than trapping.
    public func active() async throws -> Program? {
        try await queue.read { database in try Self.fetchActive(database) }
    }

    /// The program `id`, active or not, or `nil`; validated like `active()`. Not on `ProgramRepository`: the
    /// builder (F11) may promote it when it edits a block that is not the active one.
    public func program(id: ProgramID) async throws -> Program? {
        try await queue.read { database in try ProgramRows.program(id, in: database) }
    }

    /// Saves `program` as given, in one write transaction.
    /// - First it is re-validated through `Slot.init` and `Program.init`, so a slot or week edited out of range
    ///   throws `SlotValidationError` or `ProgramValidationError` and nothing is written.
    /// - Then each of its rows is compared with the stored one: a new or changed row is written, an unchanged
    ///   one keeps its `updated_at`, and a stored week, day, slot or miss the program no longer has is
    ///   soft-deleted.
    /// - When `program.isActive`, every other program is made inactive.
    ///
    /// Two weeks, days or slots sharing an id, or a week, day or slot id that another stored program holds (live
    /// or deleted), throw `duplicateIdentifier`; a slot whose exercise is not stored throws `unknownExercise`
    /// (checked next, before any row is written); text holding U+0000 throws `nulInText`, and an inexact weight
    /// `inexactWeight`. Each leaves the database as it was.
    public func save(_ program: Program) async throws {
        let rows = try ProgramRows(program)
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            try Self.write(rows, isActive: program.isActive, in: database, at: timestamp)
        }
    }

    /// Applies `change` to the stored program `id` and saves the result, in one write transaction: the read,
    /// the change and the write, so no other write (a workout's save, which writes misses and a swap's
    /// exercise into the program) can come between them. Returns the program read back in that transaction.
    ///
    /// The result is saved through `save`'s own path (`ProgramRows`), with its checks, its errors and its
    /// row rules: only the rows that changed are written, and a result equal to the stored program writes
    /// none, so observers hear nothing. A result under another id throws `duplicateIdentifier`, before any
    /// other check. A program that is not stored, or is deleted, throws `missingRow`, and one whose rows
    /// cannot be read throws what `active()` throws (`save` it whole to repair it); `change` is then not
    /// called. Whatever is thrown, by `change` or by a check, rolls the transaction back.
    ///
    /// **`change` runs on the database's writer queue, inside the transaction.** It must not use this
    /// repository, another repository of the same database or the database itself (GRDB traps on a
    /// re-entrant access), and must not wait: every other read and write of the database waits for it.
    ///
    /// A task cancelled before the write starts, or while it waits for the writer, throws
    /// `CancellationError` and `change` is not called. Cancelled while the transaction runs, GRDB starts no
    /// later statement but the rollback, so it never commits: `CancellationError`, and nothing stored. Only
    /// a cancellation that comes once the commit has succeeded comes too late: the change is stored whole,
    /// and the call returns (`ProgramUpdateCancellationTests`).
    public func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        let timestamp = ColumnCodec.timestamp(now())
        return try await queue.write { database in
            guard let stored = try ProgramRows.program(id, in: database) else {
                throw LedgerPersistenceError.missingRow("program \(ColumnCodec.text(id))")
            }
            let changed = try change(stored)
            guard changed.id == id else {
                throw LedgerPersistenceError.duplicateIdentifier("program \(ColumnCodec.text(changed.id))")
            }
            try Self.write(ProgramRows(changed), isActive: changed.isActive, in: database, at: timestamp)
            guard let saved = try ProgramRows.program(id, in: database) else {
                throw LedgerPersistenceError.missingRow("program \(ColumnCodec.text(id))")
            }
            return saved
        }
    }

    /// Makes `id` the one active program. A program that is not stored, or deleted, throws `missingRow`.
    public func setActive(_ id: ProgramID) async throws {
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            let isStored = try Int.fetchOne(
                database,
                sql: "SELECT 1 FROM program WHERE id = ? AND deleted_at IS NULL",
                arguments: [ColumnCodec.text(id)]
            ) != nil
            guard isStored else {
                throw LedgerPersistenceError.missingRow("program \(ColumnCodec.text(id))")
            }
            try Self.activate(id, in: database, at: timestamp)
        }
    }

    /// Soft-deletes the program and its weeks, days, slots and misses in one transaction; saving it again
    /// brings them back. A deleted program is no longer active, so a revival (a stale save, or a sync) can
    /// never leave two active. Deleting a program that is not stored does nothing.
    public func delete(_ id: ProgramID) async throws {
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE program SET is_active = 0 WHERE id = ? AND deleted_at IS NULL",
                arguments: [ColumnCodec.text(id)]
            )
            try ProgramRows(deleting: id).write(database, at: timestamp)
        }
    }

    /// `active()` now, then after every change to it. The stream ends, with the error logged, when the active
    /// program cannot be read (`active()` says why).
    public func observeActive() -> AsyncStream<Program?> {
        Self.activeObservation().stream(in: queue)
    }

    /// `observeActive()`'s observation: `active()`, emitted only when it differs from the last value.
    static func activeObservation() -> DistinctObservation<Program?> {
        ValueObservation.tracking { database in try fetchActive(database) }.removeDuplicates()
    }

    /// The active live program. Should a sync ever leave two active, the one updated last wins.
    private static func fetchActive(_ database: Database) throws -> Program? {
        let sql = """
        SELECT id FROM program WHERE is_active = 1 AND deleted_at IS NULL ORDER BY updated_at DESC, id LIMIT 1
        """
        guard let id = try String.fetchOne(database, sql: sql) else {
            return nil
        }
        return try ProgramRows.program(ColumnCodec.identifier(id), in: database)
    }

    /// What `save` and `update` write, in the caller's transaction: `rows` over the stored ones and, for an
    /// active program, the one active flag.
    private static func write(_ rows: ProgramRows, isActive: Bool, in database: Database, at timestamp: String) throws {
        try rows.write(database, at: timestamp)
        if isActive {
            try activate(rows.programID, in: database, at: timestamp)
        }
    }

    /// Sets `is_active` on `id` and clears it everywhere else, touching only the rows whose flag changes.
    private static func activate(_ id: ProgramID, in database: Database, at timestamp: String) throws {
        try database.execute(
            sql: """
            UPDATE program SET is_active = (id = :id), updated_at = :timestamp
            WHERE deleted_at IS NULL AND is_active IS NOT (id = :id)
            """,
            arguments: ["id": ColumnCodec.text(id), "timestamp": timestamp]
        )
    }
}
