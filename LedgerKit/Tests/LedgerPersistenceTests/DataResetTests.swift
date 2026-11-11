import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F14 S3, criterion 6 and N20–N21: "Delete all data" over GRDB and over the linked in-memory stores, each held to
/// `DataResetContract`; then what only the database has: every table emptied but `device`, this device's id kept, a
/// failure at any point of the erase leaving every row as it was, and the deleted rows gone from the file and its WAL.
@Suite("DataReset · Delete all data", .tags(.persistence), .timeLimit(.minutes(1)))
struct DataResetTests {
    enum Kind: String, CaseIterable, Sendable {
        case grdb, inMemory
    }

    static func stores(_ kind: Kind) throws -> DataResetStores {
        switch kind {
        case .grdb:
            try grdbStores(memoryStores())
        case .inMemory:
            inMemoryStores(InMemoryStores())
        }
    }

    static func grdbStores(_ stores: LedgerStores) -> DataResetStores {
        DataResetStores(
            makeReset: { catalog in GRDBDataReset(stores.queue, catalog: catalog) },
            exercises: stores.exercises,
            programs: stores.programs,
            workouts: stores.workouts,
            events: stores.events,
            settings: stores.settings
        )
    }

    static func inMemoryStores(_ stores: InMemoryStores) -> DataResetStores {
        DataResetStores(
            makeReset: { catalog in InMemoryDataReset(stores, catalog: catalog) },
            exercises: stores.exercises,
            programs: stores.programs,
            workouts: stores.workouts,
            events: stores.events,
            settings: stores.settings
        )
    }

    @Test(
        "The erase keeps the contract clause",
        arguments: Kind.allCases,
        DataResetContract.clauses
    )
    func contract_clauseHolds(_ kind: Kind, _ clause: DataResetContract.Clause) async throws {
        let issue = try await clause.check(Self.stores(kind))
        #expect(issue == nil, "\(kind) · \(clause.name): \(issue ?? "")")
    }

    // MARK: The database's own

    /// GRDB's stores over a fresh in-memory database, at a fixed time.
    static func memoryStores() throws -> LedgerStores {
        try LedgerStores(LedgerDatabase.inMemory(), deviceID: EventBuilders.phone, now: { EventBuilders.start })
    }

    /// Every table's row count, by name, `grdb_migrations` and SQLite's own left out.
    static func rowCounts(_ queue: DatabaseQueue) async throws -> [String: Int] {
        try await queue.read { database in
            let tables = try String.fetchAll(
                database,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                """
            )
            var counts: [String: Int] = [:]
            for table in tables {
                counts[table] = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
            }
            return counts
        }
    }

    /// The GRDB stores over a fresh in-memory database, holding the contract's history and a health row.
    static func seededDatabase() async throws -> LedgerStores {
        let stores = try memoryStores()
        try await DataResetContract.seedHistory(grdbStores(stores))
        try await stores.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO device (id, kind, name, created_at) VALUES (?, 'phone', 'iPhone', '2026-11-11');
                INSERT INTO workout_health (workout_id, avg_heart_rate, created_at, updated_at)
                    VALUES ((SELECT id FROM workout LIMIT 1), 120, '2026-11-11', '2026-11-11');
                """,
                arguments: [EventBuilders.phone.rawValue.uuidString]
            )
        }
        return stores
    }

    @Test("C26. The erase empties every table of the schema but device: a table a migration adds must join the list")
    func erasedTables_areEveryTableButDevice() async throws {
        let queue = try LedgerDatabase.inMemory()
        let tables = try await Self.rowCounts(queue).keys.sorted()
        #expect(tables == (GRDBDataReset.erasedTables + ["device"]).sorted())
    }

    @Test("Every row goes but device's, the reseeded catalog's and the settings'; deleted rows and health values too")
    func erase_leavesOnlyDeviceCatalogAndSettings() async throws {
        let stores = try await Self.seededDatabase()
        let before = try await Self.rowCounts(stores.queue)
        #expect(before["workout_health"] == 1)
        #expect(before["personal_record", default: 0] > 0)
        #expect(before["workout_event"] == 1)
        #expect(before["slot_miss"] != nil)
        try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        let after = try await Self.rowCounts(stores.queue)
        let catalog = try ExerciseCatalog.seed().count
        var expected = Dictionary(uniqueKeysWithValues: GRDBDataReset.erasedTables.map { ($0, 0) })
        expected["exercise"] = catalog
        expected["settings"] = 1
        expected["device"] = 1
        let leftAsExpected = after == expected
        #expect(leftAsExpected, "\(after.filter { expected[$0.key] != $0.value })")
        let device = try await stores.queue.read { try String.fetchOne($0, sql: "SELECT id FROM device") }
        #expect(device == EventBuilders.phone.rawValue.uuidString)
    }

    /// A trigger that refuses one statement of the erase, `when` it runs.
    enum Refusal: String, CaseIterable, Sendable {
        /// Midway through the deletes: programs are gone, workouts not yet.
        case deletingWorkouts = "BEFORE DELETE ON workout"
        /// The catalog's seed, after every delete.
        case seedingTheCatalog = "BEFORE INSERT ON exercise"
        /// The last statement: the settings row.
        case writingTheSettings = "BEFORE INSERT ON settings"
    }

    @Test(
        "N20. A failure at any point of the erase leaves every row of every table as it was",
        arguments: Refusal.allCases
    )
    func failureMidErase_leavesEveryRow(_ refusal: Refusal) async throws {
        let stores = try await Self.seededDatabase()
        try await stores.queue.write { database in
            try database.execute(
                sql: "CREATE TRIGGER refuse \(refusal.rawValue) BEGIN SELECT RAISE(ABORT, 'refused'); END"
            )
        }
        let before = try await Self.rowCounts(stores.queue)
        let contentsBefore = try await DataResetContract.Contents.read(Self.grdbStores(stores))
        await #expect(throws: DatabaseError.self) {
            try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        }
        let after = try await Self.rowCounts(stores.queue)
        let countsKept = after == before
        #expect(countsKept, "\(after.filter { before[$0.key] != $0.value })")
        let contentsAfter = try await DataResetContract.Contents.read(Self.grdbStores(stores))
        let difference = contentsAfter.difference(from: contentsBefore)
        #expect(difference == nil)
    }
}
