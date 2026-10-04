import Foundation
import GRDB

/// Ledger's database, opened and migrated to the latest schema (F05). The composition root (F07) opens
/// it once and hands the queue to every GRDB repository; the queue serialises every access.
public enum LedgerDatabase {
    /// Why an existing file is refused before anything writes to it (product decision #29).
    public enum OpenError: Error, Equatable {
        /// An SQLite file Ledger did not create: tables, and no `grdb_migrations`.
        case notLedgerDatabase
        /// A Ledger database a later version of the app migrated (a downgrade): the migrations this build lacks.
        case laterSchema([String])
    }

    /// Opens the database file at `url`, creating it when missing, and migrates it. It runs in WAL mode
    /// with foreign keys on, and the file and its `-wal` and `-shm` companions get `protection`.
    ///
    /// An existing file is first read without writing (`preflight`): one that is not Ledger's, or that a later
    /// version migrated, throws `OpenError` before the WAL switch or any migration writes a byte. A file of ours
    /// with known migrations pending migrates.
    ///
    /// Give the database a directory of its own (GRDB, "Database Connections"): SQLite creates the
    /// companions next to the file. A missing directory is created with `protection` too.
    public static func open(
        at url: URL,
        protection: FileProtectionType = .completeUntilFirstUserAuthentication
    ) throws -> DatabaseQueue {
        try preflight(url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
        var configuration = baseConfiguration
        configuration.journalMode = .wal
        let queue = try DatabaseQueue(path: url.path(percentEncoded: false), configuration: configuration)
        try migrator.migrate(queue)
        try protect(url, with: protection) // after migrating, once the first write has created the -wal
        return queue
    }

    /// A private, migrated in-memory database: for tests and previews.
    public static func inMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: baseConfiguration)
        try migrator.migrate(queue)
        return queue
    }

    /// Every migration, in order (`Migrations`).
    public static var migrator: DatabaseMigrator {
        Migrations.migrator
    }

    /// Reads an existing, non-empty file through a read-only connection and accepts it only if it holds Ledger's
    /// `grdb_migrations` with identifiers this build knows, or no table at all. A missing or empty file is a new
    /// database. Whatever SQLite cannot read (not a database, no permission, a directory) throws its own error.
    static func preflight(_ url: URL) throws {
        let path = url.path(percentEncoded: false)
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int
        guard let size, size > 0 else {
            return
        }
        var configuration = baseConfiguration
        configuration.readonly = true
        let reader = try DatabaseQueue(path: path, configuration: configuration)
        defer { try? reader.close() }
        let (hasMigrations, tables) = try reader.read { database in
            try (
                database.tableExists("grdb_migrations"),
                Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sqlite_master") ?? 0
            )
        }
        guard hasMigrations else {
            if tables > 0 {
                throw OpenError.notLedgerDatabase
            }
            return
        }
        let applied = try reader.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
        let unknown = applied.filter { !migrator.migrations.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw OpenError.laterSchema(unknown)
        }
    }

    private static var baseConfiguration: Configuration {
        var configuration = Configuration()
        // GRDB's default, stated because the schema's cascades depend on it.
        configuration.foreignKeysEnabled = true
        // Wait up to 5 s for another connection's lock rather than fail at once (GRDB's default): two first opens
        // of one WAL file race its -shm recovery, as the app and its widget extension will (F07 S2 fix round 1).
        configuration.busyMode = .timeout(5)
        return configuration
    }

    /// Sets `protection` on the database file and on those of its companions that exist now. SQLite
    /// keeps the WAL companions while the queue is open, and this runs on every open.
    private static func protect(_ url: URL, with protection: FileProtectionType) throws {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path(percentEncoded: false) + suffix
            if fileManager.fileExists(atPath: path) {
                try fileManager.setAttributes([.protectionKey: protection], ofItemAtPath: path)
            }
        }
    }
}
