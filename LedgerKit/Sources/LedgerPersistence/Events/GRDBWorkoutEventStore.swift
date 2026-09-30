import Foundation
import GRDB
import LedgerDomain

/// `WorkoutEventStore` over the `workout_event` table (ADR-004 rule 5; F05 implementation notes,
/// "Event store vs the contract"). One row per envelope, keyed by `uidx_event_key`
/// (workout, device, seq). Only `payload` is read back as an envelope.
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
    public func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        let rows = try envelopes.map(EnvelopeRow.init)
        let createdAt = ColumnCodec.timestamp(now())
        return try await queue.write { database in
            var fresh: [EventEnvelope] = []
            for row in rows {
                let stored = try Data.fetchOne(
                    database,
                    sql: "SELECT payload FROM workout_event WHERE workout_id = ? AND device_id = ? AND seq = ?",
                    arguments: [row.workoutID, row.deviceID, row.seq]
                )
                if let stored {
                    guard try EnvelopeCodec.decode(stored) == row.envelope else {
                        throw EngineError.conflictingEnvelope(row.envelope.key)
                    }
                    continue
                }
                try database.execute(
                    sql: """
                    INSERT INTO workout_event (workout_id, device_id, seq, wall_clock, payload, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [row.workoutID, row.deviceID, row.seq, row.wallClock, row.payload, createdAt]
                )
                fresh.append(row.envelope)
            }
            return fresh
        }
    }

    public func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope] {
        let payloads = try await queue.read { database in
            try Data.fetchAll(
                database,
                sql: "SELECT payload FROM workout_event WHERE workout_id = ? ORDER BY id",
                arguments: [ColumnCodec.text(workout)]
            )
        }
        return try payloads.map(EnvelopeCodec.decode)
    }

    /// The largest stored seq in unsigned order: a seq above `Int64.max` is stored negative
    /// (`ColumnCodec.column(seq:)`) and outranks every non-negative one.
    public func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64? {
        let stored = try await queue.read { database in
            try Int64.fetchOne(
                database,
                sql: """
                SELECT seq FROM workout_event WHERE workout_id = ? AND device_id = ?
                ORDER BY seq < 0 DESC, seq DESC LIMIT 1
                """,
                arguments: [ColumnCodec.text(workout), ColumnCodec.text(device)]
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

    public func compact(workout: WorkoutID) async throws {
        try await queue.write { database in
            try database.execute(
                sql: "DELETE FROM workout_event WHERE workout_id = ?",
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
