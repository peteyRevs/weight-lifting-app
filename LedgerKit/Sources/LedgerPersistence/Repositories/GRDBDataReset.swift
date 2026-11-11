import Foundation
import GRDB
import LedgerDomain
import os

/// `DataReset` over the stores' queue (F14 S3, ruling A1): "Delete all data" as an in-place erase of the open database,
/// then the file compacted so the deleted rows leave the disk.
///
/// **The erase is one write transaction** (N20). The bundled catalog is read and the settings encoded before it opens;
/// inside it, every table but `device` is emptied, children first, so no foreign key is ever left dangling, then the
/// catalog is seeded afresh (`GRDBExerciseRepository.seed`, the launch's own seed) and the settings row written.
/// Whatever throws inside rolls all of it back. GRDB interrupts the write of a cancelled task, which rolls back as a
/// failure does, so a cancelled erase is whole or absent.
///
/// **Then the disk** (N21): `VACUUM` rebuilds the file without the freed pages that still hold the deleted rows, and a
/// `TRUNCATE` checkpoint copies the rebuilt pages into the file and empties the `-wal`, whose older frames hold them
/// too. Both run after the commit, on the queue, never on the main actor. They are best-effort: a failure is logged,
/// and the erase, already committed, stands.
public struct GRDBDataReset: DataReset {
    /// Every table the erase empties, children before their parents: everything but `device`, this install's own row
    /// (C26). `MigrationTests`' sibling, `DataResetTests.erasedTables_areEveryTableButDevice`, fails when a migration
    /// adds a table this list lacks.
    static let erasedTables = [
        "slot_miss", "slot", "day_template", "program_week", "program",
        "logged_set", "personal_record", "workout_health", "workout_exercise", "workout",
        "workout_event", "exercise", "settings"
    ]

    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date
    private let catalog: @Sendable () throws -> [Exercise]
    private let catalogVersion: Int

    /// - Parameters:
    ///   - now: the clock for the reseeded rows' `created_at` and `updated_at`; the composition root passes the
    ///     injected
    ///     date.
    ///   - catalog: the exercises seeded after the erase, read before it begins; the bundled catalog by default. The
    ///     tests pass one the database refuses, to prove that nothing is erased then.
    ///   - catalogVersion: the version `catalog` is seeded at.
    public init(
        _ queue: DatabaseQueue,
        now: @escaping @Sendable () -> Date = Date.init,
        catalog: @escaping @Sendable () throws -> [Exercise] = { try ExerciseCatalog.seed() },
        catalogVersion: Int = ExerciseCatalog.version
    ) {
        self.queue = queue
        self.now = now
        self.catalog = catalog
        self.catalogVersion = catalogVersion
    }

    public func eraseAll(restoring settings: Settings) async throws {
        let records = try GRDBExerciseRepository.catalogRecords(catalog())
        let payload = try SettingsCodec.encode(settings)
        let timestamp = ColumnCodec.timestamp(now())
        let version = catalogVersion
        try await queue.write { database in
            for table in Self.erasedTables {
                try database.execute(sql: "DELETE FROM \(table)")
            }
            try GRDBExerciseRepository.seed(records, version: version, at: timestamp, in: database)
            try GRDBSettingsRepository.replace(payload: payload, updatedAt: timestamp, in: database)
        }
        await compact()
    }

    /// Rebuilds the file and empties the `-wal` (N21), logging a failure: the erase is already committed.
    private func compact() async {
        do {
            try await queue.vacuum()
            try await queue.writeWithoutTransaction { database in
                _ = try database.checkpoint(.truncate)
            }
        } catch is CancellationError {
            // The lifter's task ended after the commit: the next erase, or SQLite's own checkpoints, reclaim the
            // pages. A cancellation is not a failure to log (standards §8).
        } catch {
            Logger.persistence.error("Delete all data: the file could not be compacted after the erase: \(error)")
        }
    }
}
