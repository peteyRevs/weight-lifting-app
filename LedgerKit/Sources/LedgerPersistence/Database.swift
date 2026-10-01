import Foundation
import GRDB

/// Ledger's database, opened and migrated to the latest schema (F05). The composition root (F07) opens
/// it once and hands the queue to every GRDB repository; the queue serialises every access.
public enum LedgerDatabase {
    /// Opens the database file at `url`, creating it when missing, and migrates it. It runs in WAL mode
    /// with foreign keys on, and the file and its `-wal` and `-shm` companions get `protection`.
    ///
    /// Give the database a directory of its own (GRDB, "Database Connections"): SQLite creates the
    /// companions next to the file. A missing directory is created with `protection` too.
    public static func open(
        at url: URL,
        protection: FileProtectionType = .completeUntilFirstUserAuthentication
    ) throws -> DatabaseQueue {
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

    private static var baseConfiguration: Configuration {
        var configuration = Configuration()
        // GRDB's default, stated because the schema's cascades depend on it.
        configuration.foreignKeysEnabled = true
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
