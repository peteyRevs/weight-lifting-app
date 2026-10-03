import Foundation
import GRDB
@testable import LedgerPersistence
import Testing

/// Criterion 1: the schema as `LedgerDatabase` creates it, pinned migration by migration: `Fixtures/schema-v001.sql`
/// and `schema-v002.sql` are the `sqlite_master` text of every table and index after each one. A merged migration
/// is frozen, so a fixture is only ever added, with the migration that changes the schema.
@Suite("Schema", .tags(.persistence))
struct SchemaTests {
    /// Every migration, and the fixture of the schema just after it.
    static let migrations = [("v001_createSchema", "schema-v001"), ("v002_workoutStartedIndex", "schema-v002")]

    @Test("Each migration leaves the tables and indexes of its committed Fixtures/schema-vNNN.sql", arguments: 0 ..< 2)
    func eachMigration_matchesCommittedDDL(index: Int) throws {
        let (migration, fixture) = Self.migrations[index]
        let queue = try DatabaseQueue()
        try LedgerDatabase.migrator.migrate(queue, upTo: migration)
        let actual = try queue.read(Self.dump)
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "sql", subdirectory: "Fixtures"))
        let expected = try String(contentsOf: url, encoding: .utf8)
        #expect(actual == expected, "a merged migration never changes; add a new one. The schema is now:\n\(actual)")
    }

    @Test("A new database is at the last migration's schema")
    func newDatabase_isAtTheLatestSchema() throws {
        let url = try #require(Bundle.module.url(
            forResource: "schema-v002",
            withExtension: "sql",
            subdirectory: "Fixtures"
        ))
        #expect(try LedgerDatabase.inMemory().read(Self.dump) == String(contentsOf: url, encoding: .utf8))
    }

    @Test("Foreign keys are on, every migration is applied, and the migration list is the committed one")
    func inMemory_foreignKeysOn_allApplied() throws {
        let queue = try LedgerDatabase.inMemory()
        let all = Self.migrations.map(\.0)
        #expect(try queue.read { try Bool.fetchOne($0, sql: "PRAGMA foreign_keys") } == true)
        #expect(try queue.read { try LedgerDatabase.migrator.appliedIdentifiers($0) } == Set(all))
        // Append-only (engineering-standards §6): a merged migration is never renamed, reordered or removed.
        #expect(LedgerDatabase.migrator.migrations == all)
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
