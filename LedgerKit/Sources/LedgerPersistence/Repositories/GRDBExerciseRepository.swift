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

    /// The exercises whose name or short name contains `query`, ignoring case and diacritics (Pete,
    /// 2026-09-30; product decision #23), with `equipment` and the primary muscle `muscle` when given, in name
    /// order. A blank query matches every exercise. The text is matched in Swift, never in SQL, so `%` and `_`
    /// are plain characters; it is matched on the two text columns before a row is decoded, so only matches pay
    /// for decoding.
    public func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
        let needle = ExerciseSearch.key(query)
        return try await queue.read { database in
            try Self.fetch(database, equipment: equipment, muscle: muscle) { row in
                ExerciseSearch.matches(row, needle: needle)
            }
        }
    }

    /// Inserts `exercise`, or overwrites the stored one with its id (bringing it back if it was deleted).
    /// `catalog_version` is left as it is. An inexact start load throws `inexactWeight`.
    public func save(_ exercise: Exercise) async throws {
        let record = ExerciseRecord(exercise)
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in try record.upsert(database, at: timestamp) }
    }

    /// Seeds the bundled catalog, or upgrades it additively, in one write transaction (criterion 11):
    /// - It runs only when `version` is above the applied version, the largest `catalog_version` of a catalog
    ///   row. A second run at the same version, or a lower one, changes nothing.
    /// - An entry whose id is stored (deleted or not) is left as it is. Every other entry is inserted as a
    ///   catalog row (`isCustom` false), so re-seeding never duplicates a catalog row.
    /// - An entry is inserted even when its name matches a stored exercise's, custom or not, ignoring case and
    ///   diacritics: alternatives, program templates and history refer to catalog ids, so every one must
    ///   exist (orchestrator, 2026-09-30). The clash is logged; the stored exercise is left as it is.
    /// - Every catalog row the catalog lists then records `version` in `catalog_version`, so the applied
    ///   version moves up even when an upgrade adds nothing.
    ///
    /// Custom rows are never written. An inexact start load throws `inexactWeight` and seeds nothing.
    public func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
        let records = catalog.map { entry in
            var catalogEntry = entry
            catalogEntry.isCustom = false
            return ExerciseRecord(catalogEntry)
        }
        let timestamp = ColumnCodec.timestamp(now())
        try await queue.write { database in
            let applied = try Int.fetchOne(
                database,
                sql: "SELECT MAX(catalog_version) FROM exercise WHERE is_custom = 0"
            )
            guard applied.map({ $0 < version }) ?? true else {
                return
            }
            let storedIDs = try Set(String.fetchAll(database, sql: "SELECT id FROM exercise"))
            let storedNames = try Set(
                String.fetchAll(database, sql: "SELECT name FROM exercise WHERE deleted_at IS NULL")
                    .map(ExerciseSearch.key)
            )
            let mark = try database.cachedStatement(
                sql: "UPDATE exercise SET catalog_version = ? WHERE id = ? AND is_custom = 0"
            )
            for record in records {
                if !storedIDs.contains(record.rowID) {
                    if storedNames.contains(ExerciseSearch.key(record.exercise.name)) {
                        Logger.persistence.notice(
                            "Seeded catalog exercise \(record.rowID, privacy: .public), named like a stored one"
                        )
                    }
                    try record.upsert(database, at: timestamp)
                }
                try mark.execute(arguments: [version, record.rowID])
            }
        }
    }

    /// `all()` now, then after every change to the table.
    public func observeAll() -> AsyncStream<[Exercise]> {
        ValueObservation.tracking { database in try Self.fetch(database) }
            .removeDuplicates()
            .stream(in: queue)
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

/// How exercise text is compared (Pete, 2026-09-30; product decision #23): trimmed, and folded so that case
/// and diacritics never matter ("Élévation" and "elevation" are one key). The folding is the same in every
/// locale, so results do not depend on the device's language.
enum ExerciseSearch {
    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether an `exercise` row's name or short name contains `needle`, a `key`. An empty needle matches.
    static func matches(_ row: Row, needle: String) -> Bool {
        needle.isEmpty || ["name", "short_name"].contains { column in
            String.fromDatabaseValue(row[column]).map { key($0).contains(needle) } ?? false
        }
    }

    /// `exercises` by name key, then by id, so equal names keep one order.
    static func sorted(_ exercises: [Exercise]) -> [Exercise] {
        exercises
            .map { (name: key($0.name), id: $0.id.rawValue.uuidString, exercise: $0) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
            .map(\.exercise)
    }
}
