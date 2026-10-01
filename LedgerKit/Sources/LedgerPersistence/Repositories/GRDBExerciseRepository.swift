import Foundation
import GRDB
import LedgerDomain
import os

/// `ExerciseRepository` over the `exercise` table: the bundled catalog (F03, seeded by `seedIfNeeded`) and the
/// lifter's custom exercises. Deleted rows (`deleted_at`) are never returned.
public struct GRDBExerciseRepository: ExerciseRepository {
    private let queue: DatabaseQueue
    private let now: @Sendable () -> Date

    /// - Parameter now: the clock for `created_at` and `updated_at`; the composition root passes the injected
    ///   date.
    public init(_ queue: DatabaseQueue, now: @escaping @Sendable () -> Date = Date.init) {
        self.queue = queue
        self.now = now
    }

    /// Every exercise, in `ExerciseSearch` name order. A row this app cannot read (a muscle group a later
    /// version added, or damage) is logged and left out, and stays stored.
    public func all() async throws -> [Exercise] {
        try await queue.read { database in try Self.fetch(database) }
    }

    /// The exercise `id`, or `nil`. A row this app cannot read throws `LedgerPersistenceError`.
    public func exercise(id: ExerciseID) async throws -> Exercise? {
        try await queue.read { database in
            try ExerciseRecord.fetchOne(
                database,
                sql: "SELECT * FROM exercise WHERE id = ? AND deleted_at IS NULL",
                arguments: [ColumnCodec.text(id)]
            )?.exercise
        }
    }

    /// The exercises whose name or short name contains `query`, ignoring case and diacritics
    /// (`ExerciseSearch`; Pete, 2026-09-30; product decision #23), with `equipment` and the primary muscle
    /// `muscle` when given, in name order. A blank query matches every exercise. The text is matched in Swift,
    /// never in SQL, so `%` and `_` are plain characters; it is matched on the two text columns before a row is
    /// decoded, so only matches pay for decoding.
    public func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
        let needle = ExerciseSearch.key(query)
        return try await queue.read { database in
            try Self.fetch(database, equipment: equipment, muscle: muscle) { row in
                ExerciseSearch.matches(
                    name: String.fromDatabaseValue(row["name"]) ?? "",
                    shortName: String.fromDatabaseValue(row["short_name"]) ?? "",
                    needle: needle
                )
            }
        }
    }

    /// Inserts `exercise`, or overwrites the stored one with its id (bringing it back if it was deleted). An
    /// unchanged exercise is left alone, so its `updated_at` stays (M4's last-writer-wins sync). An inexact
    /// start load throws `inexactWeight`.
    ///
    /// A saved row is the lifter's: its `catalog_version` is cleared, so a catalog upgrade never refreshes it
    /// (product decision #24).
    public func save(_ exercise: Exercise) async throws {
        let record = ExerciseRecord(exercise)
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            let stored = try Row.fetchAll(
                database,
                sql: "SELECT * FROM exercise WHERE id = ? AND deleted_at IS NULL",
                arguments: [record.rowID]
            )
            try ExerciseRecord.write([record], over: stored, in: database, at: timestamp)
            try database.execute(
                sql: "UPDATE exercise SET catalog_version = NULL WHERE id = ? AND catalog_version IS NOT NULL",
                arguments: [record.rowID]
            )
        }
    }

    /// Seeds the bundled catalog, or upgrades it, in one write transaction (criterion 11; product decision #24):
    /// - It runs only when `version` is above the applied version, the largest `catalog_version` of a catalog
    ///   row. A second run at the same version, or a lower one, changes nothing. A stored version that is not
    ///   an integer throws `malformedColumn`.
    /// - An entry whose id is not stored is inserted as a catalog row (`isCustom` false), even when its name
    ///   matches a stored exercise's, custom or not, ignoring case and diacritics: alternatives, program
    ///   templates and history refer to catalog ids, so every one must exist (orchestrator, 2026-09-30). The
    ///   clash is logged; the stored exercise is left as it is.
    /// - An entry whose id is a live catalog row of an older version refreshes that row in place: its content
    ///   becomes the entry's, keeping `id` and `created_at`, and `updated_at` moves only if the content changed.
    /// - Each row inserted or refreshed records `version` in `catalog_version`, so the applied version moves up
    ///   even when an upgrade changes nothing.
    ///
    /// A custom exercise, a catalog row the lifter saved, and a deleted row are never written; nor is a row
    /// the catalog no longer lists. An inexact start load throws `inexactWeight` and seeds nothing.
    public func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
        // One record per id (F03 checks ids are unique; should a broken bundle repeat one, its last entry wins).
        let records = Dictionary(
            catalog.map { entry in
                var catalogEntry = entry
                catalogEntry.isCustom = false
                return (entry.id, ExerciseRecord(catalogEntry))
            },
            uniquingKeysWith: { _, last in last }
        ).values
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            guard try Self.appliedVersion(database).map({ $0 < version }) ?? true else {
                return
            }
            let (written, replaced) = try Self.upgrade(records, in: database, to: version)
            try ExerciseRecord.write(written, over: replaced, in: database, at: timestamp)
            let mark = try database.cachedStatement(sql: "UPDATE exercise SET catalog_version = ? WHERE id = ?")
            for record in written {
                try mark.execute(arguments: [version, record.rowID])
            }
        }
    }

    /// What a seed at `version` writes: the records whose id is not stored, and those whose id is a live catalog
    /// row of an older version, with the stored rows the latter replace. A new record named like a stored
    /// exercise is logged.
    private static func upgrade(
        _ records: some Collection<ExerciseRecord>,
        in database: Database,
        to version: Int
    ) throws -> (written: [ExerciseRecord], replaced: [Row]) {
        let storedIDs = try Set(DatabaseValue.fetchAll(database, sql: "SELECT id FROM exercise"))
        let refreshable = try Row.fetchAll(
            database,
            sql: "SELECT * FROM exercise WHERE deleted_at IS NULL AND is_custom = 0 AND catalog_version < ?",
            arguments: [version]
        )
        let refreshableIDs = Set(refreshable.map { $0["id"] as DatabaseValue })
        let storedNames = try liveNameKeys(database)
        let written = records.filter { record in
            let id = record.rowID.databaseValue
            if storedIDs.contains(id) {
                return refreshableIDs.contains(id)
            }
            if storedNames.contains(ExerciseSearch.key(record.exercise.name)) {
                Logger.persistence.notice(
                    "Seeded catalog exercise \(record.rowID, privacy: .public), named like a stored one"
                )
            }
            return true
        }
        let writtenIDs = Set(written.map(\.rowID.databaseValue))
        return (written, refreshable.filter { writtenIDs.contains($0["id"] as DatabaseValue) })
    }

    /// `all()` now, then after every change to the table.
    public func observeAll() -> AsyncStream<[Exercise]> {
        Self.allObservation().stream(in: queue)
    }

    /// `observeAll()`'s observation: `all()`, emitted only when it differs from the last value.
    static func allObservation() -> DistinctObservation<[Exercise]> {
        ValueObservation.tracking { database in try fetch(database) }.removeDuplicates()
    }

    /// The applied catalog version, the largest `catalog_version` of a catalog row, or `nil` before the first
    /// seed. Read strictly: a value that is not an integer throws `malformedColumn`, where GRDB would clamp a
    /// `REAL` beyond `Int64` to `Int64.max`, and so stop every later upgrade (S2-2).
    private static func appliedVersion(_ database: Database) throws -> Int? {
        let row = try Row.fetchOne(
            database,
            sql: "SELECT MAX(catalog_version) AS catalog_version FROM exercise WHERE is_custom = 0"
        )
        return try row.flatMap { try ColumnReader(row: $0, table: "exercise").optionalInteger("catalog_version") }
    }

    /// The `ExerciseSearch.key` of every live exercise's name; a name that is not text is skipped.
    private static func liveNameKeys(_ database: Database) throws -> Set<String> {
        try Set(
            DatabaseValue.fetchAll(database, sql: "SELECT name FROM exercise WHERE deleted_at IS NULL")
                .compactMap(String.fromDatabaseValue)
                .map(ExerciseSearch.key)
        )
    }

    /// The readable live exercises with `equipment` and the primary muscle `muscle` when given, and whose row
    /// `matches`, in name order.
    private static func fetch(
        _ database: Database,
        equipment: Equipment? = nil,
        muscle: MuscleGroup? = nil,
        where matches: (Row) -> Bool = { _ in true }
    ) throws -> [Exercise] {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT * FROM exercise WHERE deleted_at IS NULL
                AND (:equipment IS NULL OR equipment = :equipment) AND (:muscle IS NULL OR primary_muscle = :muscle)
            """,
            arguments: ["equipment": equipment?.rawValue, "muscle": muscle?.rawValue]
        )
        return ExerciseSearch.sorted(rows.filter(matches).compactMap(readable))
    }

    /// The row's exercise, or `nil` (logged) when this app cannot read it.
    private static func readable(_ row: Row) -> Exercise? {
        do {
            return try ExerciseRecord(row: row).exercise
        } catch {
            let id = String.fromDatabaseValue(row["id"]) ?? "?"
            Logger.persistence.error("Left out exercise row \(id, privacy: .public), which is unreadable: \(error)")
            return nil
        }
    }
}
