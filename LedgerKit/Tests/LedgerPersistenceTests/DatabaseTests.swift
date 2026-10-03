import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// `LedgerDatabase.open(at:protection:)` on a file in the temporary directory: WAL, foreign keys, a
/// reopen that keeps data and migrates nothing twice, and data protection.
@Suite("LedgerDatabase · file", .tags(.persistence), .timeLimit(.minutes(1)))
struct DatabaseTests {
    /// The iOS and watchOS simulators accept a protection class but keep none (their volume has no data
    /// protection), so a read-back there is always `nil`. The macOS host (`check.sh --fast`) and a device
    /// keep it.
    static let keepsFileProtection: Bool = {
        #if targetEnvironment(simulator)
            false
        #else
            true
        #endif
    }()

    @Test("Opening a new file creates its directory and migrates it, in WAL mode with foreign keys on")
    func open_newFile_isWALAndMigrated() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try LedgerDatabase.open(at: directory.file("store/ledger.sqlite"))
        let (journal, foreignKeys, applied) = try queue.read { database in
            try (
                String.fetchOne(database, sql: "PRAGMA journal_mode"),
                Bool.fetchOne(database, sql: "PRAGMA foreign_keys"),
                LedgerDatabase.migrator.appliedIdentifiers(database)
            )
        }
        #expect(journal == "wal")
        #expect(foreignKeys == true)
        #expect(applied == ["v001_createSchema", "v002_workoutStartedIndex"])
    }

    @Test("Reopening a file keeps its rows and applies no migration twice")
    func open_existingFile_keepsRows_andMigratesOnce() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let url = directory.file("ledger.sqlite")
        try await GRDBSettingsRepository(LedgerDatabase.open(at: url)).save(Settings.default)
        let reopened = try LedgerDatabase.open(at: url)
        #expect(try await GRDBSettingsRepository(reopened).load() == .default)
        let migrations = try await reopened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM grdb_migrations") }
        #expect(migrations == 2)
    }

    /// Close-out finding 5: the test must pass while the Mac or the device is locked. It first opens with the
    /// product's class (`completeUntilFirstUserAuthentication`, open after the first unlock), then reopens the
    /// file with `completeUnlessOpen` while the first queue is still open, and never reopens a file of that
    /// class, which a locked device refuses. So it needs no `.complete` and runs on the host and devices alike.
    @Test(
        "Every open sets the requested protection on the file and its -wal; the default is the product's class",
        .disabled(if: !keepsFileProtection, "the simulators accept a protection class but keep none")
    )
    func open_protectsTheFileAndItsCompanions() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let url = directory.file("ledger.sqlite")
        let paths = [url.path(percentEncoded: false), url.path(percentEncoded: false) + "-wal"]
        func protections() throws -> [FileProtectionType?] {
            try paths
                .map { try FileManager.default.attributesOfItem(atPath: $0)[.protectionKey] as? FileProtectionType }
        }
        // Each queue stays open while it is checked, so the -wal exists.
        let product = try LedgerDatabase.open(at: url)
        try withExtendedLifetime(product) {
            let defaults = try protections()
            #expect(defaults == Array(repeating: .completeUntilFirstUserAuthentication, count: 2))
            let reopened = try LedgerDatabase.open(at: url, protection: .completeUnlessOpen)
            try withExtendedLifetime(reopened) {
                let requested = try protections()
                #expect(requested == [.completeUnlessOpen, .completeUnlessOpen])
            }
        }
    }
}
