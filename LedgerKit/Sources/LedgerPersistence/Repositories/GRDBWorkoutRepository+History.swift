import Foundation
import GRDB
import LedgerDomain

/// The History list's reads (F13 S1, N1 and N2): the `workout` rows alone, through `idx_workout_started`, with the
/// totals each row stores "for queries that do not load the sets" and the `pr_count` `RecordReplay` keeps right.
public extension GRDBWorkoutRepository {
    /// One entry per live finished workout, newest first by start, then id (product decision #26). A row this app
    /// cannot read (an id, a date or a case a later version wrote, or damage) is logged and left out, and stays
    /// stored. Its exercises and sets are not read, so a workout whose sets are damaged is still listed (A5).
    func historyEntries() async throws -> [HistoryEntry] {
        try await queue.read { database in try Self.fetchHistoryEntries(in: database) }
    }

    /// `historyEntries()` now, then after every change that alters it. The observation reads the `workout` table
    /// alone, so a live workout's set taps, which write `workout_event`, never wake it; a write to a workout that
    /// leaves every entry as it was emits nothing. A read that fails ends the stream.
    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        Self.historyObservation.stream(in: queue)
    }
}

extension GRDBWorkoutRepository {
    /// `observeHistoryEntries()`'s observation: `historyEntries()`, emitted only when it differs from the last value.
    static var historyObservation: DistinctObservation<[HistoryEntry]> {
        ValueObservation.tracking { database in try fetchHistoryEntries(in: database) }.removeDuplicates()
    }

    static func fetchHistoryEntries(in database: Database) throws -> [HistoryEntry] {
        let sql = """
        SELECT * FROM workout WHERE deleted_at IS NULL AND phase = 'finished' AND ended_at IS NOT NULL
        ORDER BY started_at DESC, id
        """
        return try Row.fetchAll(database, sql: sql).compactMap { row in
            row.readable(as: WorkoutRecord.databaseTableName, HistoryEntry.init(row:))
        }
    }
}

extension HistoryEntry {
    /// The entry of a `workout` row: its own fields as `WorkoutRecord` reads them, with the stored totals.
    init(row: Row) throws {
        try WorkoutRows.requireTextID(of: row, in: WorkoutRecord.databaseTableName)
        let workout = try WorkoutRecord(row: row).workout
        let read = ColumnReader(row: row, table: WorkoutRecord.databaseTableName)
        try self.init(
            id: workout.id,
            name: workout.name,
            tag: workout.tag,
            isDeload: workout.isDeload,
            startedAt: workout.startedAt,
            // `elapsed(at:)` reads its argument only when the workout has no end, and a listed one has one.
            elapsed: workout.elapsed(at: workout.startedAt),
            volume: Volume(e7gReps: read.integer("volume_e7g_reps")),
            doneSets: read.integer("done_sets"),
            totalSets: read.integer("total_sets"),
            prCount: read.integer("pr_count")
        )
    }
}
