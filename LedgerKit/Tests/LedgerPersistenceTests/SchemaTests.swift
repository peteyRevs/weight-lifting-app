import Foundation
import GRDB
@testable import LedgerPersistence
import Testing

/// Criterion 1: schema v001 as `LedgerDatabase` creates it, pinned by `Fixtures/schema-v001.sql`, the
/// `sqlite_master` text of every table and index. v001 is frozen once merged, so the fixture changes
/// only when a later migration adds to the schema.
@Suite("Schema v001", .tags(.persistence))
struct SchemaTests {
    @Test("A new database's tables and indexes match the committed Fixtures/schema-v001.sql")
    func v001_newDatabase_matchesCommittedDDL() throws {
        let actual = try LedgerDatabase.inMemory().read(Self.dump)
        let url = try #require(Bundle.module.url(
            forResource: "schema-v001",
            withExtension: "sql",
            subdirectory: "Fixtures"
        ))
        let expected = try String(contentsOf: url, encoding: .utf8)
        #expect(actual == expected, "a merged migration never changes; add a new one. The schema is now:\n\(actual)")
    }

    @Test("Foreign keys are on, v001 is applied, and the migration list is the committed one")
    func inMemory_foreignKeysOn_v001Applied() throws {
        let queue = try LedgerDatabase.inMemory()
        #expect(try queue.read { try Bool.fetchOne($0, sql: "PRAGMA foreign_keys") } == true)
        #expect(try queue.read { try LedgerDatabase.migrator.appliedIdentifiers($0) } == ["v001_createSchema"])
        // Append-only (engineering-standards §6): a merged migration is never renamed, reordered or removed.
        #expect(LedgerDatabase.migrator.migrations == ["v001_createSchema"])
    }

    @Test("A child row needs its parent, and deleting the parent cascades to its children")
    func foreignKeys_rejectOrphans_andCascade() throws {
        let queue = try LedgerDatabase.inMemory()
        let stamp = "2026-09-16T05:20:00.000Z"
        try queue.write { database in
            let insertDay = """
            INSERT INTO day_template (id, program_id, position, name, tag, created_at, updated_at)
            VALUES ('D', 'P', 0, 'Upper A', 'UA', ?, ?)
            """
            #expect(throws: DatabaseError.self) { try database.execute(sql: insertDay, arguments: [stamp, stamp]) }
            try database.execute(
                sql: """
                INSERT INTO program (id, name, start_date, created_at, updated_at)
                VALUES ('P', 'Block', '2026-09-14', ?, ?)
                """,
                arguments: [stamp, stamp]
            )
            try database.execute(sql: insertDay, arguments: [stamp, stamp])
            try database.execute(sql: "DELETE FROM program WHERE id = 'P'")
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM day_template") == 0)
        }
    }

    @Test("No table has a UNIQUE constraint but the local-only event key (ADR-002: CloudKit-shaped)")
    func uniqueIndexes_areOnlyPrimaryKeys_andTheEventKey() throws {
        let unique = try LedgerDatabase.inMemory().read { database in
            try String.fetchAll(database, sql: """
            SELECT m.name || '.' || i.name FROM sqlite_master AS m, pragma_index_list(m.name) AS i
            WHERE m.type = 'table' AND m.name NOT LIKE 'grdb%' AND i."unique" = 1 AND i.origin != 'pk'
            """)
        }
        #expect(unique == ["workout_event.uidx_event_key"])
    }

    /// Every table's and index's `CREATE` text, tables first, each by name.
    static func dump(_ database: Database) throws -> String {
        try String.fetchAll(database, sql: """
        SELECT sql || ';' FROM sqlite_master
        WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite%' AND name NOT LIKE 'grdb%'
        ORDER BY type DESC, name
        """).joined(separator: "\n") + "\n"
    }
}
