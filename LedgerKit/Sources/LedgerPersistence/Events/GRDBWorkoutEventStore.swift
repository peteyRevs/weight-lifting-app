import Foundation
import GRDB
import LedgerDomain
import os

/// `WorkoutEventStore` over the `workout_event` table (ADR-004 rule 5; F05 implementation notes,
/// "Event store vs the contract"). One row per envelope, keyed by `uidx_event_key`
/// (workout, device, seq). Only `payload`, decoded by its `payload_version`, is read back as an envelope.
public struct GRDBWorkoutEventStore: WorkoutEventStore {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock for `created_at`; the composition root passes the injected date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// One transaction, so a conflict rolls back the whole batch. For each envelope, in order: a new
    /// key is inserted and returned; a stored key whose envelope decodes `==` is skipped (compared
    /// decoded, not as bytes); any other stored envelope throws `conflictingEnvelope`. The transaction
    /// reads its own inserts, so a conflict within the batch is caught too.
    ///
    /// A stored key whose row this app version cannot read (a later payload version, or damage) is
    /// repaired: the incoming envelope overwrites the row and is returned as newly stored, so the host
    /// rebuilds (orchestrator decision, 2026-09-30, amended by fix round 2). A key names one envelope, so
    /// the incoming one is that row's copy.
    public func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        let rows = try envelopes.map(EnvelopeRow.init)
        let createdAt = ColumnCodec.timestamp(now())
        return try await queue.write { database in
            let statements = try AppendStatements(database)
            return try rows.filter { try statements.store($0, createdAt: createdAt) }.map(\.envelope)
        }
    }

    /// The envelopes this app version can read. An unreadable row is logged and left stored.
    public func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope] {
        try await storedPayloads(of: workout).compactMap(\.readable)
    }

    public func unreadableCount(for workout: WorkoutID) async throws -> Int {
        try await storedPayloads(of: workout).count { $0.readable == nil }
    }

    /// The largest stored seq in unsigned order: a seq above `Int64.max` is stored negative
    /// (`ColumnCodec.column(seq:)`) and outranks every non-negative one, so the largest negative one wins
    /// if there is any. Unreadable rows count: their keys are taken.
    public func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64? {
        let key = [ColumnCodec.text(workout), ColumnCodec.text(device)]
        let stored = try await queue.read { database in
            try Int64.fetchOne(
                database,
                sql: """
                SELECT COALESCE(
                    (SELECT MAX(seq) FROM workout_event WHERE workout_id = ? AND device_id = ? AND seq < 0),
                    (SELECT MAX(seq) FROM workout_event WHERE workout_id = ? AND device_id = ?))
                """,
                arguments: StatementArguments(key + key)
            )
        }
        return stored.map(ColumnCodec.seq(column:))
    }

    public func uncompactedWorkoutIDs() async throws -> [WorkoutID] {
        let stored = try await queue.read { database in
            try String.fetchAll(database, sql: "SELECT DISTINCT workout_id FROM workout_event")
        }
        return try stored.map { text throws(LedgerPersistenceError) in try ColumnCodec.identifier(text) }
    }

    /// Read from the `wall_clock` column, so unreadable rows count. The column holds `NULL` for a
    /// non-finite stamp; the bound also skips an infinity written by another writer.
    public func newestWallClock() async throws -> Date? {
        let seconds = try await queue.read { database in
            try Double.fetchOne(
                database,
                sql: "SELECT MAX(wall_clock) FROM workout_event WHERE abs(wall_clock) <= ?",
                arguments: [Double.greatestFiniteMagnitude]
            )
        }
        return seconds.map(ColumnCodec.date(seconds:))
    }

    public func compact(workout: WorkoutID) async throws {
        try await queue.write { database in try Self.deleteLog(of: workout, in: database) }
    }

    /// Deletes every row of the workout's log, unreadable ones included, in the caller's transaction:
    /// `compact(workout:)`, and the last step of the save that drops a finished workout's log with it
    /// (`GRDBWorkoutRepository.materialize(_:slotUpdates:droppingLog:)`).
    static func deleteLog(of workout: WorkoutID, in database: Database) throws {
        try database.execute(
            sql: "DELETE FROM workout_event WHERE workout_id = ?",
            arguments: [ColumnCodec.text(workout)]
        )
    }

    private func storedPayloads(of workout: WorkoutID) async throws -> [StoredPayload] {
        try await queue.read { database in
            try StoredPayload.fetchAll(
                database,
                sql: "SELECT id, payload_version, payload FROM workout_event WHERE workout_id = ? ORDER BY id",
                arguments: [ColumnCodec.text(workout)]
            )
        }
    }
}

/// An envelope's column values, encoded before the write transaction opens so it stays short.
private struct EnvelopeRow: Sendable {
    let envelope: EventEnvelope
    let workoutID: String
    let deviceID: String
    let seq: Int64
    /// `NULL` for a non-finite stamp, so `MAX(wall_clock)` is the largest finite one (ADR-004
    /// amendment, "Recovery skips only non-finite stamps").
    let wallClock: Double?
    let payload: Data

    init(_ envelope: EventEnvelope) throws {
        self.envelope = envelope
        workoutID = ColumnCodec.text(envelope.workoutID)
        deviceID = ColumnCodec.text(envelope.device)
        seq = ColumnCodec.column(seq: envelope.seq)
        wallClock = ColumnCodec.finiteSeconds(envelope.wallClock)
        payload = try EnvelopeCodec.encode(envelope)
    }
}

/// `append`'s three statements, prepared once per transaction.
private struct AppendStatements {
    let find: Statement
    let insert: Statement
    let repair: Statement

    init(_ database: Database) throws {
        find = try database.cachedStatement(sql: """
        SELECT id, payload_version, payload FROM workout_event WHERE workout_id = ? AND device_id = ? AND seq = ?
        """)
        insert = try database.cachedStatement(sql: """
        INSERT INTO workout_event (workout_id, device_id, seq, wall_clock, payload_version, payload, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """)
        repair = try database.cachedStatement(sql: """
        UPDATE workout_event SET wall_clock = ?, payload_version = ?, payload = ? WHERE id = ?
        """)
    }

    /// Stores `row` and returns `true` when it is new (inserted, or repairing an unreadable row), `false`
    /// when its envelope is already stored; throws `conflictingEnvelope` for a different stored envelope.
    func store(_ row: EnvelopeRow, createdAt: String) throws -> Bool {
        guard let stored = try StoredPayload.fetchOne(find, arguments: [row.workoutID, row.deviceID, row.seq]) else {
            try insert.execute(arguments: [
                row.workoutID, row.deviceID, row.seq, row.wallClock, EnvelopeCodec.version, row.payload, createdAt
            ])
            return true
        }
        switch Result(catching: stored.envelope) {
        case let .success(envelope):
            guard envelope == row.envelope else {
                throw EngineError.conflictingEnvelope(row.envelope.key)
            }
            return false
        case let .failure(error):
            try repair.execute(arguments: [row.wallClock, EnvelopeCodec.version, row.payload, stored.id])
            Logger.persistence.notice("workout_event row \(stored.id) was unreadable, repaired: \(error)")
            return true
        }
    }
}

/// A stored row's payload as written. A version or payload of the wrong type (damage, or a version beyond
/// a 32-bit `Int` on an arm64_32 watch) reads as `nil` rather than trapping, and makes the row unreadable.
private struct StoredPayload: FetchableRecord, Sendable {
    let id: Int64
    let version: Int?
    let bytes: Data?

    init(row: Row) {
        id = row["id"]
        version = Int.fromDatabaseValue(row["payload_version"])
        bytes = Data.fromDatabaseValue(row["payload"])
    }

    /// The envelope; throws when this app version cannot read the row.
    func envelope() throws -> EventEnvelope {
        guard let version else {
            throw LedgerPersistenceError.malformedColumn("workout_event.payload_version")
        }
        guard let bytes else {
            throw LedgerPersistenceError.malformedColumn("workout_event.payload")
        }
        return try EnvelopeCodec.decode(bytes, version: version)
    }

    /// The envelope, or `nil` when this app version cannot read the row, which is logged. The row stays
    /// stored until a readable copy repairs it or a later version reads it.
    var readable: EventEnvelope? {
        do {
            return try envelope()
        } catch {
            Logger.persistence.error("workout_event row \(id) is unreadable, kept: \(error)")
            return nil
        }
    }
}
