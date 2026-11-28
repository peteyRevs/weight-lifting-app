import Foundation
import GRDB
import LedgerDomain

/// `CompanionStore` over v003's `finished_log`, `companion_state` and `companion_last_performance` tables.
public struct GRDBCompanionStore: CompanionStore {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock for `companion_state.updated_at`; the composition root passes the injected date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    // MARK: Finished logs

    public func saveFinishedLog(_ record: FinishedWorkoutRecord, createdAt: Date) async throws {
        let payload = try CompanionCodec.encode(record)
        let created = try ColumnCodec.seconds(createdAt)
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO finished_log (workout_id, device_id, payload, health_uuid, created_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (workout_id) DO UPDATE SET device_id = excluded.device_id, payload = excluded.payload,
                    health_uuid = excluded.health_uuid
                """,
                arguments: [
                    ColumnCodec.text(record.workoutID), ColumnCodec.text(record.device), payload,
                    record.healthKitUUID?.uuidString, created
                ]
            )
        }
    }

    /// A row this build cannot read (a later codec version, or damage) is logged and left out, and stays stored
    /// (`Row.readable`): one unreadable row must not hold back the rest of the outbox.
    public func unacknowledgedLogs() async throws -> [FinishedLogEntry] {
        try await queue.read { database in
            try Row.fetchAll(database, sql: """
            SELECT workout_id AS id, payload, created_at, enqueued_at FROM finished_log
            WHERE acked_at IS NULL ORDER BY created_at, workout_id
            """).compactMap { row in
                row.readable(as: "finished_log") { row in
                    let columns = ColumnReader(row: row, table: "finished_log")
                    guard let payload = Data.fromDatabaseValue(row["payload"]) else {
                        throw LedgerPersistenceError.malformedColumn("finished_log.payload")
                    }
                    return try FinishedLogEntry(
                        record: CompanionCodec.decode(FinishedWorkoutRecord.self, from: payload),
                        createdAt: columns.date("created_at"),
                        enqueuedAt: columns.optionalDate("enqueued_at")
                    )
                }
            }
        }
    }

    public func markEnqueued(_ workouts: [WorkoutID], at date: Date) async throws {
        try await stamp("enqueued_at", of: workouts, at: date)
    }

    public func acknowledge(_ workouts: [WorkoutID], at date: Date) async throws {
        try await stamp("acked_at", of: workouts, at: date)
    }

    /// Sets `column` to `date` on the rows of `workouts` where it is still `NULL`, in one write.
    private func stamp(_ column: String, of workouts: [WorkoutID], at date: Date) async throws {
        let seconds = try ColumnCodec.seconds(date)
        let ids = workouts.map(ColumnCodec.text)
        try await queue.write { database in
            let statement = try database.makeStatement(
                sql: "UPDATE finished_log SET \(column) = ? WHERE workout_id = ? AND \(column) IS NULL"
            )
            for id in ids {
                try statement.execute(arguments: [seconds, id])
            }
        }
    }

    public func compactAcknowledged() async throws {
        try await queue.write { database in
            try database.execute(sql: "DELETE FROM finished_log WHERE acked_at IS NOT NULL")
        }
    }

    public func pruneArchives(now: Date) async throws {
        let cutoff = try ColumnCodec.seconds(now) - FinishedLogEntry.archiveRetention
        try await queue.write { database in
            try database.execute(sql: "DELETE FROM finished_log WHERE created_at < ?", arguments: [cutoff])
        }
    }

    // MARK: State

    /// A row this build cannot read throws (`CompanionCodecError` for the context, `malformedColumn` for a column of
    /// the wrong kind) rather than reading as empty, which would let a stale revision through.
    public func state() async throws -> CompanionState {
        try await queue.read { database in
            let sql = "SELECT context, program_sha256 FROM companion_state WHERE id = 'singleton'"
            guard let row = try Row.fetchOne(database, sql: sql) else {
                return .empty
            }
            return try CompanionState(
                context: Self.blob(row, "context").map { try CompanionCodec.decode(CompanionContext.self, from: $0) },
                programFileSHA256: Self.blob(row, "program_sha256")
            )
        }
    }

    public func saveState(_ state: CompanionState) async throws {
        let context = try state.context.map(CompanionCodec.encode)
        let updatedAt = ColumnCodec.timestamp(now())
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT OR REPLACE INTO companion_state (id, context, program_sha256, updated_at)
                VALUES ('singleton', ?, ?, ?)
                """,
                arguments: [context, state.programFileSHA256, updatedAt]
            )
        }
    }

    /// The column's bytes, nil for `NULL`; any other kind of value throws `malformedColumn`.
    private static func blob(_ row: Row, _ column: String) throws -> Data? {
        let value: DatabaseValue = row[column]
        guard value.isNull || Data.fromDatabaseValue(value) != nil else {
            throw LedgerPersistenceError.malformedColumn("companion_state.\(column)")
        }
        return Data.fromDatabaseValue(value)
    }

    // MARK: Last performance

    public func replaceLastPerformance(_ performance: [ExerciseID: LastPerformance]) async throws {
        let rows = try performance.map { id, line throws(LedgerPersistenceError) in
            try StatementArguments([
                ColumnCodec.text(id), ColumnCodec.seconds(line.date), line.sets, line.reps, line.load.e7g()
            ])
        }
        try await queue.write { database in
            try database.execute(sql: "DELETE FROM companion_last_performance")
            let statement = try database.makeStatement(sql: """
            INSERT INTO companion_last_performance (exercise_id, date, sets, reps, load_e7g) VALUES (?, ?, ?, ?, ?)
            """)
            for arguments in rows {
                try statement.execute(arguments: arguments)
            }
        }
    }

    /// A column of the wrong kind throws `malformedColumn`, and an exercise id that is not a UUID
    /// `malformedIdentifier` (`ColumnReader`).
    public func lastPerformance() async throws -> [ExerciseID: LastPerformance] {
        try await queue.read { database in
            var performance: [ExerciseID: LastPerformance] = [:]
            let sql = "SELECT exercise_id, date, sets, reps, load_e7g FROM companion_last_performance"
            for row in try Row.fetchAll(database, sql: sql) {
                let columns = ColumnReader(row: row, table: "companion_last_performance")
                try performance[columns.identifier("exercise_id")] = try LastPerformance(
                    date: columns.date("date"),
                    sets: columns.integer("sets"),
                    reps: columns.integer("reps"),
                    load: Weight(e7g: columns.integer("load_e7g"))
                )
            }
            return performance
        }
    }
}
