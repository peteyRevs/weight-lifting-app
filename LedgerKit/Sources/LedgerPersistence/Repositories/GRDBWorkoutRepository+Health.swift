import Foundation
import GRDB
import LedgerDomain

/// `WorkoutHealthRepository` over v001's `workout_health` and v003's `finished_log` (F19 S3b): the upsert keeps the
/// row's `created_at` and stamps `updated_at`; the pending list joins each finished log to its live workout.
extension GRDBWorkoutRepository: WorkoutHealthRepository {
    public func saveHealth(_ health: WorkoutHealth, of workout: WorkoutID) async throws {
        let id = ColumnCodec.text(workout)
        let stamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            let live = try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS (SELECT 1 FROM workout WHERE id = ? AND deleted_at IS NULL)",
                arguments: [id]
            )
            guard live == true else {
                throw LedgerPersistenceError.missingRow("workout \(id)")
            }
            try database.execute(
                sql: """
                INSERT INTO workout_health (workout_id, avg_heart_rate, max_heart_rate, active_energy_kcal,
                    hk_workout_uuid, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (workout_id) DO UPDATE SET avg_heart_rate = excluded.avg_heart_rate,
                    max_heart_rate = excluded.max_heart_rate, active_energy_kcal = excluded.active_energy_kcal,
                    hk_workout_uuid = excluded.hk_workout_uuid, updated_at = excluded.updated_at
                """,
                arguments: [
                    id, health.avgHeartRate, health.maxHeartRate, health.activeEnergyKcal,
                    health.healthKitUUID.uuidString, stamp, stamp
                ]
            )
        }
    }

    /// `active_energy_kcal` is `REAL`: a fraction (v001's fixture holds one) reads rounded to the nearest kilocalorie.
    /// A `NULL` UUID, or a column of the wrong kind, throws `malformedColumn`.
    public func health(of workout: WorkoutID) async throws -> WorkoutHealth? {
        try await queue.read { database in
            let sql = """
            SELECT avg_heart_rate, max_heart_rate, active_energy_kcal, hk_workout_uuid FROM workout_health
            WHERE workout_id = ?
            """
            guard let row = try Row.fetchOne(database, sql: sql, arguments: [ColumnCodec.text(workout)]) else {
                return nil
            }
            let columns = ColumnReader(row: row, table: "workout_health")
            return try WorkoutHealth(
                healthKitUUID: Self.uuid(columns, "hk_workout_uuid"),
                avgHeartRate: columns.optionalInteger("avg_heart_rate"),
                maxHeartRate: columns.optionalInteger("max_heart_rate"),
                activeEnergyKcal: Self.kilocalories(row)
            )
        }
    }

    /// A row this build cannot read is logged and left out, and stays stored (`Row.readable`).
    public func pendingHealth() async throws -> [PendingHealth] {
        try await queue.read { database in
            try Row.fetchAll(database, sql: """
            SELECT log.workout_id AS id, log.health_uuid, log.created_at FROM finished_log AS log
            JOIN workout ON workout.id = log.workout_id AND workout.deleted_at IS NULL
            WHERE log.health_uuid IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM workout_health WHERE workout_health.workout_id = log.workout_id)
            ORDER BY log.created_at, log.workout_id
            """).compactMap { row in
                row.readable(as: "finished_log") { row in
                    let columns = ColumnReader(row: row, table: "finished_log")
                    return try PendingHealth(
                        workoutID: columns.identifier("id"),
                        healthKitUUID: Self.uuid(columns, "health_uuid"),
                        createdAt: columns.date("created_at")
                    )
                }
            }
        }
    }

    private static func uuid(_ columns: ColumnReader, _ column: String) throws(LedgerPersistenceError) -> UUID {
        guard let uuid = try UUID(uuidString: columns.text(column)) else {
            throw .malformedColumn("\(columns.table).\(column)")
        }
        return uuid
    }

    private static func kilocalories(_ row: Row) throws(LedgerPersistenceError) -> Int? {
        let stored: DatabaseValue = row["active_energy_kcal"]
        if stored.isNull {
            return nil
        }
        guard let value = Double.fromDatabaseValue(stored), let kilocalories = Int(exactly: value.rounded()) else {
            throw .malformedColumn("workout_health.active_energy_kcal")
        }
        return kilocalories
    }
}
