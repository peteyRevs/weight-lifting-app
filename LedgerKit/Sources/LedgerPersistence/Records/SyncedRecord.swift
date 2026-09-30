import GRDB

/// A row of a table shaped for CloudKit (ADR-002): `id` plus content columns, and the row metadata
/// `created_at`, `updated_at` and `deleted_at` (ISO 8601 text, `ColumnCodec.timestamp`). A record encodes the
/// content only, `id` included; `upsert` and `write(_:over:in:at:)` write the metadata, and a diff compares
/// content only.
protocol SyncedRecord: FetchableRecord, EncodableRecord, TableRecord {
    /// The `id` column's text.
    var rowID: String { get }
}

extension SyncedRecord {
    /// Inserts the row, or overwrites its content and brings it back from a soft delete. `created_at` is
    /// written once; `updated_at` is `timestamp` either way.
    func upsert(_ database: Database, at timestamp: String) throws {
        try Self.upsert(databaseDictionary, in: database, at: timestamp)
    }

    private static func upsert(
        _ dictionary: [String: DatabaseValue],
        in database: Database,
        at timestamp: String
    ) throws {
        let content = dictionary.sorted { $0.key < $1.key }
        let columns = content.map(\.key)
        let assignments = columns.filter { $0 != "id" }.map { "\($0) = excluded.\($0)" }
            + ["updated_at = excluded.updated_at", "deleted_at = NULL"]
        let placeholders = Array(repeating: "?", count: columns.count + 2)
        let sql = """
        INSERT INTO \(databaseTableName) (\(columns.joined(separator: ", ")), created_at, updated_at)
        VALUES (\(placeholders.joined(separator: ", ")))
        ON CONFLICT (id) DO UPDATE SET \(assignments.joined(separator: ", "))
        """
        let values = content.map(\.value) + [timestamp.databaseValue, timestamp.databaseValue]
        try database.cachedStatement(sql: sql).execute(arguments: StatementArguments(values))
    }

    /// Makes `stored`, the live rows that `records` replace (fetched with `SELECT *`), into `records`, in the
    /// caller's transaction. A new or changed row is upserted and an unchanged one left alone, so its
    /// `updated_at` stays; a stored row missing from `records` is soft-deleted. Stored rows are compared as
    /// column values, never decoded, so a save repairs a damaged row rather than failing on it.
    ///
    /// Throws `duplicateIdentifier` when two records share an id: both would land in one row.
    static func write(_ records: [Self], over stored: [Row], in database: Database, at timestamp: String) throws {
        var ids = Set<String>()
        for record in records where !ids.insert(record.rowID).inserted {
            throw LedgerPersistenceError.duplicateIdentifier("\(databaseTableName) \(record.rowID)")
        }
        let storedByID = Dictionary(
            stored.compactMap { row in String.fromDatabaseValue(row["id"]).map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )
        for record in records {
            let content = try record.databaseDictionary
            if let row = storedByID[record.rowID], content.allSatisfy({ (row[$0.key] as DatabaseValue) == $0.value }) {
                continue // unchanged
            }
            try upsert(content, in: database, at: timestamp)
        }
        let removed = storedByID.keys.filter { !ids.contains($0) }.sorted()
        let softDelete = try database.cachedStatement(
            sql: "UPDATE \(databaseTableName) SET deleted_at = ?, updated_at = ? WHERE id = ?"
        )
        for id in removed {
            try softDelete.execute(arguments: [timestamp, timestamp, id])
        }
    }
}
