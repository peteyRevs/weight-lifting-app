import Foundation
import GRDB
@testable import LedgerPersistence
import Testing

/// `LedgerDatabase.open`'s read-only preflight (decision #29, F7-S2-2): a file that is not Ledger's, or that a later
/// version migrated, is refused before a byte of it is written; a file of ours still migrates.
@Suite("LedgerDatabase · preflight", .tags(.persistence), .timeLimit(.minutes(1)))
struct DatabasePreflightTests {
    /// Every file in `directory` with its bytes, for "untouched". A `-shm` file is listed but its bytes are not
    /// compared: it is SQLite's shared-memory index of the `-wal`, which every reader, read-only ones included,
    /// updates; it holds no data, and SQLite rebuilds it from the `-wal`.
    static func snapshot(_ directory: TemporaryDirectory) throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
        return try Dictionary(uniqueKeysWithValues: names.map { name in
            try (name, name.hasSuffix("-shm") ? Data() : Data(contentsOf: directory.file(name)))
        })
    }

    static func applied(_ queue: DatabaseQueue) throws -> [String] {
        try queue.read { try LedgerDatabase.migrator.appliedIdentifiers($0).sorted() }
    }

    @Test("A SQLite file that is not Ledger's throws notLedgerDatabase, and no byte or file changes")
    func foreignDatabase_isRefused_untouched() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let url = directory.file("ledger.sqlite")
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let foreign = try DatabaseQueue(path: url.path(percentEncoded: false))
        try foreign.write { try $0.execute(sql: "CREATE TABLE notes (body TEXT); INSERT INTO notes VALUES ('mine')") }
        try foreign.close()
        let before = try Self.snapshot(directory)
        #expect(throws: LedgerDatabase.OpenError.notLedgerDatabase) { try LedgerDatabase.open(at: url) }
        #expect(try Self.snapshot(directory) == before)
    }

    @Test("A file a later version migrated (a downgrade) throws laterSchema naming the unknown migrations, untouched")
    func laterSchema_isRefused_untouched() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let url = directory.file("ledger.sqlite")
        let queue = try LedgerDatabase.open(at: url)
        try queue.write { database in
            try database.execute(sql: "INSERT INTO grdb_migrations VALUES ('v999_fromTheFuture')")
            try database.execute(sql: "CREATE TABLE future (x INTEGER)")
        }
        try queue.close()
        let before = try Self.snapshot(directory)
        #expect(throws: LedgerDatabase.OpenError.laterSchema(["v999_fromTheFuture"])) {
            try LedgerDatabase.open(at: url)
        }
        let after = try Self.snapshot(directory)
        #expect(after == before, "\(before.mapValues(\.count)) → \(after.mapValues(\.count))")
    }

    @Test("A file of Ledger's with a known migration pending migrates and opens")
    func pendingKnownMigration_migrates() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let url = directory.file("ledger.sqlite")
        let first = try #require(LedgerDatabase.migrator.migrations.first)
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let old = try DatabaseQueue(path: url.path(percentEncoded: false))
        try LedgerDatabase.migrator.migrate(old, upTo: first)
        try old.close()
        let queue = try LedgerDatabase.open(at: url)
        #expect(try Self.applied(queue) == LedgerDatabase.migrator.migrations.sorted())
    }

    @Test("An empty file, and an SQLite file with no table yet, are new databases")
    func emptyAndTablelessFiles_areNew() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let empty = directory.file("empty/ledger.sqlite")
        try FileManager.default.createDirectory(
            at: empty.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: empty)
        #expect(try Self.applied(LedgerDatabase.open(at: empty)) == LedgerDatabase.migrator.migrations.sorted())
        let tableless = directory.file("tableless/ledger.sqlite")
        try FileManager.default.createDirectory(
            at: tableless.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let header = try DatabaseQueue(path: tableless.path(percentEncoded: false))
        try header.writeWithoutTransaction { try $0.execute(sql: "PRAGMA user_version = 7") }
        try header.close()
        #expect(try Self.applied(LedgerDatabase.open(at: tableless)) == LedgerDatabase.migrator.migrations.sorted())
    }
}
