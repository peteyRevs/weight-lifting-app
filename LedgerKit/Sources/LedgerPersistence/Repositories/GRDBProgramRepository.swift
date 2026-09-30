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
    /// Two days or slots sharing an id throw `duplicateIdentifier`, an inexact weight `inexactWeight`, and a
    /// slot whose exercise is not stored a foreign-key `DatabaseError`; each leaves the database as it was.
    public func save(_ program: Program) async throws {
        let rows = try ProgramRows(program)
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            try rows.write(database, at: timestamp)
            if program.isActive {
                try Self.activate(program.id, in: database, at: timestamp)
            }
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
    /// brings them back. Deleting a program that is not stored does nothing.
    public func delete(_ id: ProgramID) async throws {
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in try ProgramRows(deleting: id).write(database, at: timestamp) }
    }

    /// `active()` now, then after every change to it. The stream ends, with the error logged, when the active
    /// program cannot be read (`active()` says why).
    public func observeActive() -> AsyncStream<Program?> {
        ValueObservation.tracking { database in try Self.fetchActive(database) }
            .removeDuplicates()
            .stream(in: queue)
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
