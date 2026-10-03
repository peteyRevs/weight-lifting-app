import Foundation
import GRDB
@testable import LedgerPersistence
import Testing

/// F05 S1 adversarial round 1: schema v001 checked against the brief and ADR-002 rather than against its
/// own fixture: migration idempotence, every foreign key enforced and indexed, no `UNIQUE` beyond the
/// local-only event key.
@Suite("Adversarial S1 · schema v001", .tags(.persistence))
struct SchemaAdversarialTests {
    /// The brief's foreign keys (child.column → parent, on delete), plus `personal_record` (S1 notes).
    static let foreignKeys: Set<String> = [
        "program_week.program_id → program CASCADE", "day_template.program_id → program CASCADE",
        "slot.day_template_id → day_template CASCADE", "slot.exercise_id → exercise NO ACTION",
        "slot_miss.slot_id → slot CASCADE", "workout_exercise.workout_id → workout CASCADE",
        "logged_set.workout_exercise_id → workout_exercise CASCADE", "workout_health.workout_id → workout CASCADE",
        "personal_record.workout_id → workout CASCADE"
    ]

    @Test("Migrating an already migrated database again, with rows in it, changes nothing")
    func migrateAgain_changesNothing() throws {
        let queue = try LedgerDatabase.inMemory()
        try queue.write { database in
            try database.execute(sql: """
            INSERT INTO device (id, kind, name, created_at) VALUES ('D', 'watch', 'Pete''s Watch', 'then')
            """)
        }
        let before = try queue.read(SchemaTests.dump)
        try LedgerDatabase.migrator.migrate(queue)
        try LedgerDatabase.migrator.migrate(queue)
        #expect(try queue.read(SchemaTests.dump) == before)
        // Every migration once (S3 fix round 3 added v002, product decision #26).
        #expect(try queue.read(LedgerDatabase.migrator.appliedIdentifiers) == [
            "v001_createSchema", "v002_workoutStartedIndex"
        ])
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM device") } == 1)
        #expect(try queue.read(LedgerDatabase.migrator.hasCompletedMigrations))
    }

    @Test("A fresh database passes SQLite's integrity and foreign key checks")
    func freshDatabase_isIntact() throws {
        let queue = try LedgerDatabase.inMemory()
        #expect(try queue.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") } == "ok")
        #expect(try queue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }.isEmpty)
    }

    @Test("The declared foreign keys are the brief's, with its delete rules")
    func foreignKeys_areTheBriefs() throws {
        let declared = try LedgerDatabase.inMemory().read { database in
            try String.fetchAll(database, sql: """
            SELECT m.name || '.' || f."from" || ' → ' || f."table" || ' ' || f.on_delete
            FROM sqlite_master AS m, pragma_foreign_key_list(m.name) AS f WHERE m.type = 'table'
            """)
        }
        #expect(Set(declared) == Self.foreignKeys)
        #expect(declared.count == Self.foreignKeys.count)
    }

    @Test("Every table with a foreign key refuses a row whose references dangle")
    func everyChildTable_refusesDanglingReferences() throws {
        let queue = try LedgerDatabase.inMemory()
        let children = Set(Self.foreignKeys.map { String($0.prefix { $0 != "." }) })
        for table in children.sorted() {
            try queue.write { database in
                let insert = try Self.danglingInsert(into: table, database)
                let error = #expect(throws: DatabaseError.self, "\(table)") { try database.execute(sql: insert) }
                #expect(
                    error?.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY,
                    "\(table): \(String(describing: error))"
                )
            }
        }
    }

    @Test("Every foreign key column leads an index, so a cascade or parent delete never scans")
    func everyForeignKeyColumn_leadsAnIndex() throws {
        let unindexed = try LedgerDatabase.inMemory().read { database in
            try String.fetchAll(database, sql: """
            SELECT m.name || '.' || f."from" FROM sqlite_master AS m, pragma_foreign_key_list(m.name) AS f
            WHERE m.type = 'table' AND NOT EXISTS (
                SELECT 1 FROM pragma_index_list(m.name) AS i, pragma_index_info(i.name) AS c
                WHERE c.seqno = 0 AND c.name = f."from"
            )
            """)
        }
        #expect(unindexed.isEmpty)
    }

    @Test("No UNIQUE in any DDL but the event key's, primary keys are single id columns, and events have no FK")
    func uniqueness_isOnlyTheEventKey() throws {
        let queue = try LedgerDatabase.inMemory()
        let (uniqueDDL, keys, eventKey, eventForeignKeys) = try queue.read { database in
            try (
                String.fetchAll(database, sql: """
                SELECT name FROM sqlite_master WHERE sql LIKE '%UNIQUE%' AND name NOT LIKE 'grdb%'
                """),
                String.fetchAll(database, sql: """
                SELECT m.name || '.' || c.name FROM sqlite_master AS m, pragma_table_info(m.name) AS c
                WHERE m.type = 'table' AND m.name NOT LIKE 'grdb%' AND m.name NOT LIKE 'sqlite%' AND c.pk > 0
                """),
                String.fetchAll(database, sql: "SELECT name FROM pragma_index_info('uidx_event_key') ORDER BY seqno"),
                Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pragma_foreign_key_list('workout_event')")
            )
        }
        #expect(uniqueDDL == ["uidx_event_key"])
        #expect(keys.allSatisfy { $0.hasSuffix(".id") || $0 == "workout_health.workout_id" }, "\(keys)")
        #expect(eventKey == ["workout_id", "device_id", "seq"])
        #expect(eventForeignKeys == 0)
    }

    /// An `INSERT` into `table` with a filler for every `NOT NULL` column and `'dangling'` in every foreign key.
    static func danglingInsert(into table: String, _ database: Database) throws -> String {
        let foreign = try Set(String.fetchAll(
            database,
            sql: "SELECT \"from\" FROM pragma_foreign_key_list(?)",
            arguments: [table]
        ))
        let columns = try Row.fetchAll(
            database,
            sql: "SELECT name, type, \"notnull\" FROM pragma_table_info(?)",
            arguments: [table]
        )
        let values: [(String, String)] = columns.compactMap { column in
            let (name, type, required) = (column["name"] as String, column["type"] as String, column["notnull"] as Bool)
            if foreign.contains(name) {
                return (name, "'dangling'")
            }
            guard required else {
                return nil
            }
            return (name, ["INTEGER": "0", "REAL": "0.5", "BLOB": "x'00'"][type] ?? "'filler'")
        }
        let names = values.map(\.0).joined(separator: ", ")
        return "INSERT INTO \(table) (\(names)) VALUES (\(values.map(\.1).joined(separator: ", ")))"
    }
}
