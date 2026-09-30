import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 1: the event store on a WAL file, as the apps run it. The contract on a file;
/// a copy taken mid-session (what a crash leaves: an un-checkpointed `-wal`, no `-shm`); a torn last WAL
/// frame; file protection on every platform, checked where the platform reports it.
@Suite("Adversarial S1 · file database", .tags(.persistence), .timeLimit(.minutes(1)))
struct FileDatabaseAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    @Test("The contract holds on a WAL file database", arguments: WorkoutEventStoreContract.clauses)
    func contract_holdsOnAFile(_ clause: WorkoutEventStoreContract.Clause) async throws {
        let directory = TemporaryDirectory("contractOnFile\(clause.name)")
        defer { try? directory.remove() } // cleanup only
        let queue = try LedgerDatabase.open(at: directory.file("ledger.sqlite"))
        let issue = try await clause.check(GRDBWorkoutEventStore(queue))
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("A copy taken mid-session, as a crash leaves the files, reopens with every committed batch")
    func crashCopy_reopensWithEveryCommittedBatch() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let live = try await LiveDatabase(in: directory)
        let (crashed, mainOnly) = try withExtendedLifetime(live.queue) { // still open: no checkpoint on close
            try (
                Self.copy(live.url, to: directory.file("crashed/ledger.sqlite"), tornBytes: 0),
                Self.copy(live.url, to: directory.file("main-only/ledger.sqlite"), tornBytes: nil)
            )
        }
        let log = live.log
        #expect(try Self.eventRows(mainOnly) == 0, "the rows were already checkpointed: the -wal played no part")
        let reopened = try LedgerDatabase.open(at: crashed)
        #expect(try await Set(GRDBWorkoutEventStore(reopened).envelopes(for: Contract.workout)) == Set(log))
        #expect(try await reopened.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") } == "ok")
        #expect(try await reopened.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
    }

    @Test("A torn last WAL frame loses the whole last batch and nothing before it")
    func tornWAL_losesTheWholeLastBatchOnly() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let live = try await LiveDatabase(in: directory)
        let torn = try withExtendedLifetime(live.queue) { // still open: no checkpoint on close
            try Self.copy(live.url, to: directory.file("torn/ledger.sqlite"), tornBytes: 100)
        }
        let log = live.log
        let reopened = try LedgerDatabase.open(at: torn)
        let store = GRDBWorkoutEventStore(reopened)
        #expect(try await Set(store.envelopes(for: Contract.workout)) == Set(log.prefix(25)))
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 25)
        #expect(try await reopened.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") } == "ok")
        // The lost batch appends again as new.
        #expect(try await store.append(Array(log.suffix(25))) == Array(log.suffix(25)))
    }

    @Test("The file, -wal, -shm and a new directory never carry another protection class than requested")
    func protection_isNeverAnotherClass() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let url = directory.file("store/ledger.sqlite")
        let path = url.path(percentEncoded: false)
        let queue = try LedgerDatabase.open(at: url, protection: .completeUnlessOpen)
        try withExtendedLifetime(queue) {
            let paths = [
                url.deletingLastPathComponent().path(percentEncoded: false),
                path,
                path + "-wal",
                path + "-shm"
            ]
            let classes = try paths.map { path in
                try FileManager.default.attributesOfItem(atPath: path)[.protectionKey] as? FileProtectionType
            }
            if DatabaseTests.keepsFileProtection {
                #expect(classes == Array(repeating: .completeUnlessOpen, count: 4))
            } else {
                #expect(classes.allSatisfy { $0 == nil || $0 == .completeUnlessOpen }, "\(classes)")
            }
        }
    }

    @Test("A path with spaces and percent signs opens, migrates and reopens")
    func unusualPath_opensAndReopens() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let url = directory.file("Application Support/100% ledger/ledger db.sqlite")
        _ = try await GRDBWorkoutEventStore(LedgerDatabase.open(at: url)).append([Contract.skip(1)])
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let reopened = try LedgerDatabase.open(at: url)
        #expect(try await GRDBWorkoutEventStore(reopened).envelopes(for: Contract.workout) == [Contract.skip(1)])
        let migrations = try await reopened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM grdb_migrations") }
        #expect(migrations == 1)
    }

    // MARK: Helpers

    /// Copies the database file, and its `-wal` without the last `tornBytes` (none when `nil`), but never the
    /// `-shm`: SQLite must rebuild its index from the WAL, as after a crash.
    static func copy(_ source: URL, to destination: URL, tornBytes: Int?) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (origin, target) = (source.path(percentEncoded: false), destination.path(percentEncoded: false))
        if let tornBytes {
            let wal = try Data(contentsOf: URL(filePath: origin + "-wal"))
            try wal.dropLast(tornBytes).write(to: URL(filePath: target + "-wal"))
        }
        try manager.copyItem(atPath: origin, toPath: target)
        return destination
    }

    /// The `workout_event` rows a database file holds, read by plain SQLite (0 when the table is not there).
    static func eventRows(_ url: URL) throws -> Int {
        let queue = try DatabaseQueue(path: url.path(percentEncoded: false))
        return try queue.read { database in
            try database.tableExists("workout_event")
                ? Int.fetchOne(database, sql: "SELECT COUNT(*) FROM workout_event") ?? 0 : 0
        }
    }
}

/// A file database holding 50 envelopes appended in two committed batches of 25. The caller keeps `queue`
/// open while it copies the files, so nothing is checkpointed on close.
struct LiveDatabase {
    let log = (1 ... 50).map { WorkoutEventStoreContract.skip(UInt64($0)) }
    let url: URL
    let queue: DatabaseQueue

    init(in directory: TemporaryDirectory) async throws {
        url = directory.file("live/ledger.sqlite")
        queue = try LedgerDatabase.open(at: url)
        let store = GRDBWorkoutEventStore(queue)
        _ = try await store.append(Array(log.prefix(25)))
        _ = try await store.append(Array(log.suffix(25)))
    }
}
