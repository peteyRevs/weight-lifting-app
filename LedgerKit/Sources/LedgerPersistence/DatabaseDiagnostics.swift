#if DEBUG
    import Foundation
    import GRDB
    import LedgerDomain

    /// What Debug's Diagnostics screen shows of an open database (F07 criterion 7): its file, this install's device id
    /// and every table's row count.
    public struct DatabaseDiagnostics: Equatable, Sendable {
        public struct Table: Equatable, Sendable {
            public let name: String
            public let rows: Int

            public init(name: String, rows: Int) {
                self.name = name
                self.rows = rows
            }
        }

        public let path: String
        public let deviceID: DeviceID
        /// Every table but SQLite's own, by name.
        public let tables: [Table]

        public init(path: String, deviceID: DeviceID, tables: [Table]) {
            self.path = path
            self.deviceID = deviceID
            self.tables = tables
        }
    }

    public extension LedgerStores {
        /// Reads the file's path, this device's id and every table's row count, in one read.
        func diagnostics() async throws -> DatabaseDiagnostics {
            let tables = try await queue.read { database in
                let names = try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
                        + " AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\' ORDER BY name"
                )
                return try names.map { name in
                    let rows = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(name.quotedDatabaseIdentifier)")
                    return DatabaseDiagnostics.Table(name: name, rows: rows ?? 0)
                }
            }
            return DatabaseDiagnostics(path: queue.path, deviceID: deviceID, tables: tables)
        }
    }
#endif
