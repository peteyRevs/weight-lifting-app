#if DEBUG
    import Foundation
    import GRDB
    import LedgerDomain
    @testable import LedgerPersistence
    import Testing

    /// `LedgerStores.diagnostics()`, which Debug's Diagnostics screen shows (F07 criterion 7): the file, this device
    /// and
    /// every table's row count, read from the stores themselves.
    @Suite("Database diagnostics", .tags(.persistence), .timeLimit(.minutes(1)))
    struct DatabaseDiagnosticsTests {
        static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        static let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1") ?? UUID()

        @Test("A seeded file reports its path, its device and each table's rows, by name")
        func seededFile_reportsEveryTable() async throws {
            let directory = TemporaryDirectory()
            defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
            let url = directory.file("Database/ledger.sqlite")
            let stores = try LedgerStores.open(at: url, kind: .phone, now: { Self.now }, newID: { Self.device })
            try await stores.seedCatalog()

            let diagnostics = try await stores.diagnostics()

            #expect(diagnostics.path == url.path(percentEncoded: false))
            #expect(diagnostics.deviceID == DeviceID(Self.device))
            let rows = Dictionary(uniqueKeysWithValues: diagnostics.tables.map { ($0.name, $0.rows) })
            #expect(try rows["exercise"] == ExerciseCatalog.seed().count)
            #expect(rows["device"] == 1)
            #expect(rows["workout"] == 0)
            let tables = try await stores.queue.read { database in
                try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            }
            #expect(diagnostics.tables.map(\.name) == tables.filter { !$0.hasPrefix("sqlite_") }.sorted())
        }

        @Test("SQLite's own tables are left out, and a table named like a keyword is counted")
        func internalTables_leftOut_quotedNamesCounted() async throws {
            let queue = try LedgerDatabase.inMemory()
            try await queue.write { database in
                try database
                    .execute(sql: "CREATE TABLE counter (id INTEGER PRIMARY KEY AUTOINCREMENT)") // sqlite_sequence
                try database.execute(sql: "INSERT INTO counter DEFAULT VALUES")
                try database.execute(sql: "CREATE TABLE \"order\" (id INTEGER)")
                try database.execute(sql: "INSERT INTO \"order\" VALUES (1), (2)")
            }
            let stores = LedgerStores(queue, deviceID: DeviceID(Self.device), now: { Self.now })

            let tables = try await stores.diagnostics().tables

            #expect(!tables.contains { $0.name.hasPrefix("sqlite_") })
            #expect(tables.first { $0.name == "order" }?.rows == 2)
            #expect(tables.first { $0.name == "counter" }?.rows == 1)
        }
    }
#endif
