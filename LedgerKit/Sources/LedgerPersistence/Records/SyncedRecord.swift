import GRDB

/// A row of a table shaped for CloudKit (ADR-002): `id` plus content columns, and the row metadata
/// `created_at`, `updated_at` and `deleted_at` (ISO 8601 text, `ColumnCodec.timestamp`). A record encodes the
/// content only, `id` included; `write(_:over:in:at:)` writes the metadata, and its diff compares content
/// only.
protocol SyncedRecord: FetchableRecord, EncodableRecord, TableRecord {
    /// The `id` column's text.
    var rowID: String { get }
}

extension SyncedRecord {
    /// Inserts the row `dictionary` holds, or overwrites its content and brings it back from a soft delete.
    /// `created_at` is written once; `updated_at` is `timestamp` either way.
    ///
    /// Every write of a record's content comes through here, so this is where text holding U+0000 is refused
    /// (`nulInText`): GRDB binds text as a C string, and SQLite would keep it only up to the NUL (S2-4).
    ///
    /// `statement` is the last upsert's statement, for its columns: the records of one write share their
    /// columns, so the SQL is built once a write rather than once a row.
    private static func upsert(
        _ dictionary: [String: DatabaseValue],
        in database: Database,
        at timestamp: String,
        reusing statement: inout (columns: [String], statement: Statement)?
    ) throws {
        let content = dictionary.sorted { $0.key < $1.key }
        for (column, value) in content {
            if case let .string(text) = value.storage, text.unicodeScalars.contains("\0") {
                throw LedgerPersistenceError.nulInText("\(databaseTableName).\(column)")
            }
        }
        let columns = content.map(\.key)
        if statement?.columns != columns {
            let assignments = columns.filter { $0 != "id" }.map { "\($0) = excluded.\($0)" }
                + ["updated_at = excluded.updated_at", "deleted_at = NULL"]
            let placeholders = Array(repeating: "?", count: columns.count + 2)
            let sql = """
            INSERT INTO \(databaseTableName) (\(columns.joined(separator: ", ")), created_at, updated_at)
            VALUES (\(placeholders.joined(separator: ", ")))
            ON CONFLICT (id) DO UPDATE SET \(assignments.joined(separator: ", "))
            """
            statement = try (columns, database.cachedStatement(sql: sql))
        }
        let values = content.map(\.value) + [timestamp.databaseValue, timestamp.databaseValue]
        try statement?.statement.execute(arguments: StatementArguments(values))
    }

    /// Makes `stored`, the live rows that `records` replace (fetched with `SELECT *`), into `records`, in the
    /// caller's transaction. A new or changed row is upserted and an unchanged one left alone, so its
    /// `updated_at` stays; a stored row missing from `records` is soft-deleted, in `stored`'s order. Stored rows
    /// are compared as column values, never decoded, so a save repairs a damaged row rather than failing on it.
    ///
    /// Stored rows are keyed by their `id` value as stored, whatever its storage class. A damaged id (text that
    /// is not the record's, or a blob) then matches no record and is soft-deleted by that same value, so a save
    /// repairs the row (S2-3).
    ///
    /// Throws `duplicateIdentifier` when two records share an id: both would land in one row.
    static func write(_ records: [Self], over stored: [Row], in database: Database, at timestamp: String) throws {
        var ids = Set<DatabaseValue>()
        for record in records where !ids.insert(record.rowID.databaseValue).inserted {
            throw LedgerPersistenceError.duplicateIdentifier("\(databaseTableName) \(record.rowID)")
        }
        let storedByID = Dictionary(
            stored.map { row in (row["id"] as DatabaseValue, row) },
            uniquingKeysWith: { first, _ in first }
        )
        var statement: (columns: [String], statement: Statement)?
        for record in records {
            let content = try record.databaseDictionary
            let row = storedByID[record.rowID.databaseValue]
            if let row, content.allSatisfy({ (row[$0.key] as DatabaseValue) == $0.value }) {
                continue // unchanged
            }
            try upsert(content, in: database, at: timestamp, reusing: &statement)
        }
        // In `stored`'s order, so statements run in one order on every launch (review N-c).
        let removed = stored.map { $0["id"] as DatabaseValue }.filter { !ids.contains($0) }
        let softDelete = try database.cachedStatement(
            sql: "UPDATE \(databaseTableName) SET deleted_at = ?, updated_at = ? WHERE id = ?"
        )
        for id in removed {
            try softDelete.execute(arguments: [timestamp, timestamp, id])
        }
    }
}
