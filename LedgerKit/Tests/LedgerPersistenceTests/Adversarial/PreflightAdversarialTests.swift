import Foundation
import GRDB
@testable import LedgerPersistence
import Testing

/// F07 S2 close-out: `LedgerDatabase.open`'s read-only preflight (F7-S2-2's fix) on the files a crash, a restore or a
/// foreign writer leaves: WAL files with companions, a hot WAL of our own, migrations known and unknown, a symlink,
/// and a held write lock (the new 5 s busy timeout).
@Suite("Adversarial F07 S2 close-out · open preflight", .tags(.persistence), .timeLimit(.minutes(1)))
struct PreflightAdversarialTests {
    static func folder(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PreflightAdversarial-\(ProcessInfo.processInfo.processIdentifier)-\(name)")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func bytes(_ url: URL, _ suffix: String) -> Data? {
        try? Data(contentsOf: URL(filePath: url.path(percentEncoded: false) + suffix))
    }

    /// Copies `source` and its `-wal` and `-shm` to `target` while `source` is still open: the files a crash leaves.
    static func crashCopy(of source: URL, to target: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let from = source.path(percentEncoded: false) + suffix
            if FileManager.default.fileExists(atPath: from) {
                try FileManager.default.copyItem(atPath: from, toPath: target.path(percentEncoded: false) + suffix)
            }
        }
    }

    static var wal: Configuration {
        var configuration = Configuration()
        configuration.journalMode = .wal
        return configuration
    }

    @Test("A foreign WAL file with a hot -wal and its -shm is refused; the file and its -wal stay byte for byte")
    func foreignHotWAL_refusedUntouched() throws {
        let folder = Self.folder("foreignWAL")
        defer { try? FileManager.default.removeItem(at: folder) }
        let writer = try DatabaseQueue(path: folder.appending(path: "source.sqlite").path(), configuration: Self.wal)
        try writer.write { try $0.execute(sql: "CREATE TABLE notes (x TEXT); INSERT INTO notes VALUES ('theirs')") }
        let target = folder.appending(path: "ledger.sqlite")
        try Self.crashCopy(of: folder.appending(path: "source.sqlite"), to: target)
        let (main, walBytes) = (Self.bytes(target, ""), Self.bytes(target, "-wal"))
        #expect((walBytes?.count ?? 0) > 0, "the copy holds a hot WAL")
        #expect(throws: LedgerDatabase.OpenError.notLedgerDatabase) { try LedgerDatabase.open(at: target) }
        #expect(Self.bytes(target, "") == main)
        #expect(Self.bytes(target, "-wal") == walBytes)
        try writer.close()
    }

    @Test("Ledger's own file after a crash (a hot -wal) opens, with the rows only the WAL held")
    func ourHotWAL_opensWithItsRows() throws {
        let folder = Self.folder("ourWAL")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "source/ledger.sqlite")
        let queue = try LedgerDatabase.open(at: source)
        try queue.write { try $0.execute(sql: "INSERT INTO settings VALUES ('singleton', 1, '{}', 'then')") }
        let target = folder.appending(path: "copy/ledger.sqlite")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.crashCopy(of: source, to: target)
        let reopened = try LedgerDatabase.open(at: target)
        #expect(try reopened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") } == 1)
        try queue.close()
    }

    @Test("Ledger's own file after a crash whose -shm is gone (only the -wal kept) still opens")
    func ourHotWALWithoutShm_opens() throws {
        let folder = Self.folder("ourWALnoShm")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "source/ledger.sqlite")
        let queue = try LedgerDatabase.open(at: source)
        try queue.write { try $0.execute(sql: "INSERT INTO settings VALUES ('singleton', 1, '{}', 'then')") }
        let target = folder.appending(path: "copy/ledger.sqlite")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.crashCopy(of: source, to: target)
        try FileManager.default.removeItem(atPath: target.path(percentEncoded: false) + "-shm")
        let reopened = try LedgerDatabase.open(at: target)
        #expect(try reopened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") } == 1)
        try queue.close()
    }

    @Test("grdb_migrations with a known and an unknown id throws laterSchema naming only the unknown, untouched")
    func knownAndUnknownMigrations_laterSchema() throws {
        let folder = Self.folder("mixed")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "ledger.sqlite")
        try LedgerDatabase.open(at: url).close()
        let known = try #require(LedgerDatabase.migrator.migrations.first)
        let writer = try DatabaseQueue(path: url.path())
        try writer.write { try $0.execute(sql: "INSERT INTO grdb_migrations VALUES ('v999-from-the-future')") }
        try writer.close()
        let before = Self.bytes(url, "")
        #expect(throws: LedgerDatabase.OpenError.laterSchema(["v999-from-the-future"])) {
            try LedgerDatabase.open(at: url)
        }
        #expect(Self.bytes(url, "") == before)
        #expect(known != "v999-from-the-future")
    }

    @Test("A symlink at the path to a foreign file is refused, and the file it points to is untouched")
    func symlinkToForeignFile_refused() throws {
        let folder = Self.folder("symlink")
        defer { try? FileManager.default.removeItem(at: folder) }
        let foreign = folder.appending(path: "theirs.sqlite")
        let writer = try DatabaseQueue(path: foreign.path())
        try writer.write { try $0.execute(sql: "CREATE TABLE notes (x TEXT)") }
        try writer.close()
        let link = folder.appending(path: "Database/ledger.sqlite")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: foreign)
        let before = Self.bytes(foreign, "")
        #expect(throws: LedgerDatabase.OpenError.notLedgerDatabase) { try LedgerDatabase.open(at: link) }
        #expect(Self.bytes(foreign, "") == before)
    }

    @Test("A write lock another connection holds past the busy timeout fails the open cleanly, nothing written")
    func heldWriteLock_failsCleanly() throws {
        let folder = Self.folder("busy")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "ledger.sqlite")
        try LedgerDatabase.open(at: url).close() // a database of ours, migrated, with no device row yet
        let holder = try DatabaseQueue(path: url.path(), configuration: Self.wal)
        try holder.inDatabase { database in
            try database.execute(sql: "BEGIN IMMEDIATE")
            #expect(throws: (any Error).self) {
                try LedgerStores.open(at: url, kind: .phone, now: { Date() }, newID: { UUID() })
            }
            try database.execute(sql: "ROLLBACK")
        }
        let rows = try holder.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM device") }
        #expect(rows == 0)
        try holder.close()
    }
}
