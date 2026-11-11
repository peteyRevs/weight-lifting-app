import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization
import Testing

/// F14 S3 G2 (adversarial): "Delete all data" over GRDB, attacked where the implementer's tests stop.
///
/// - The app's erase is always cancelled after its commit: the commit empties `observeActive`, the gate turns to
///   onboarding, the tabs leave the tree, and SwiftUI cancels `SettingsRoot`'s `.task`, whose group runs the erase.
///   N21's compaction runs after that commit, so it must survive the cancellation or the deleted rows stay on disk.
/// - Every table with rows, refused at its own delete, leaves everything (N20), not only the three statements the
///   implementer's trigger picks.
/// - No distinctive text the lifter typed survives in any column of any table, `device` and `grdb_migrations` included.
/// - The file passes `integrity_check` and `foreign_key_check` after one erase and after a second straight after.
@Suite("Adversarial F14 S3 · Delete all data over GRDB", .serialized, .tags(.persistence), .timeLimit(.minutes(1)))
struct DataResetAdversarialTests {
    /// The program's name, as nothing else is named, so a scan can look for it.
    static let programName = "Wombat Periodization Cycle"

    /// The names the lifter typed: a custom exercise's, two workouts', and the program's.
    static let names = [
        DataResetContract.custom.name,
        DataResetContract.workout(1).name,
        DataResetContract.workout(2).name,
        programName
    ]

    /// The contract's history, its program renamed to `programName`.
    static func seed(_ stores: LedgerStores) async throws {
        try await DataResetContract.seedHistory(DataResetTests.grdbStores(stores))
        var program = try DataResetContract.program()
        program.name = programName
        try await stores.programs.save(program)
    }

    /// Whether the file at `url`, if there is one, holds `text`'s UTF-8 bytes.
    static func file(_ url: URL, holds text: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return false
        }
        return try Data(contentsOf: url).range(of: Data(text.utf8)) != nil
    }

    /// The names of `names` still in the database file, its `-wal` or its `-shm`.
    static func traces(at url: URL) throws -> [String] {
        let files = [
            url,
            URL(filePath: url.path(percentEncoded: false) + "-wal"),
            URL(filePath: url.path(percentEncoded: false) + "-shm")
        ]
        var found: [String] = []
        for name in names {
            for file in files where try Self.file(file, holds: name) {
                found.append("\(name) in \(file.lastPathComponent)")
            }
        }
        return found
    }

    // MARK: N21 under the app's cancellation

    @Test("""
    N21 (G2). The erase's task cancelled once its write commits, as the gate's turn to onboarding cancels Settings' \
    task in the app: the deleted names still leave the file and its WAL
    """)
    func cancelledAfterCommit_stillLeavesNoTraceOnDisk() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let url = directory.file("ledger.sqlite")
        let stores = try LedgerStores.open(at: url, kind: .phone, now: { EventBuilders.start }, newID: { UUID() })
        try await Self.seed(stores)
        let written = try Self.traces(at: url)
        #expect(written.count >= Self.names.count, "the names were never written: the scan would prove nothing")

        let observer = CancelOnCommit()
        stores.queue.add(transactionObserver: observer, extent: .observerLifetime)
        let (signal, start) = AsyncStream<Void>.makeStream()
        let erase = Task {
            for await _ in signal {
                break
            }
            try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        }
        observer.task.withLock { $0 = erase }
        start.yield()
        start.finish()
        let result = await erase.result
        let erased = (try? result.get()) != nil
        #expect(erased, "the erase committed, so it reports success")
        let counts = try await DataResetTests.rowCounts(stores.queue)
        #expect(counts["workout"] == 0 && counts["program"] == 0, "the erase committed")

        let left = try Self.traces(at: url)
        #expect(left.isEmpty, "still on disk after the erase: \(left)")
    }

    // MARK: N20 at every table

    @Test("N20 (G2). A refusal at the delete of any table holding rows leaves every row of every table as it was")
    func refusalAtEveryTablesDelete_leavesEverything() async throws {
        let seeded = try await DataResetTests.seededDatabase()
        let counts = try await DataResetTests.rowCounts(seeded.queue)
        let tables = counts.filter { $0.key != "device" && $0.value > 0 }.keys.sorted()
        let empty = counts.filter { $0.value == 0 }.keys.sorted()
        #expect(tables.count >= 10, "seeded tables: \(tables); empty: \(empty)")
        for table in tables {
            let stores = try await DataResetTests.seededDatabase()
            try await stores.queue.write { database in
                try database.execute(
                    sql: "CREATE TRIGGER refuse BEFORE DELETE ON \(table) BEGIN SELECT RAISE(ABORT, 'refused'); END"
                )
            }
            let before = try await DataResetTests.rowCounts(stores.queue)
            let threw = await (try? stores.reset.eraseAll(restoring: DataResetContract.restored)) == nil
            #expect(threw, "\(table): the refused erase did not throw")
            let after = try await DataResetTests.rowCounts(stores.queue)
            let kept = after == before
            #expect(kept, "\(table): \(after.filter { before[$0.key] != $0.value })")
        }
    }

    // MARK: Nothing the lifter typed survives anywhere

    @Test("G2. After the erase no column of any table, device and grdb_migrations included, holds a name typed")
    func erase_leavesNoNameInAnyColumn() async throws {
        let stores = try DataResetTests.memoryStores()
        try await Self.seed(stores)
        let before = try await Self.cellsHolding(Self.names, in: stores.queue)
        #expect(before.count >= Self.names.count, "the names were never stored: \(before)")
        try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        let after = try await Self.cellsHolding(Self.names, in: stores.queue)
        #expect(after.isEmpty, "\(after)")
    }

    // MARK: The file afterwards

    @Test("G2. On a WAL file with an observation open, two erases in a row leave a sound file and no trace")
    func twoErasesOnAFile_leaveASoundFileAndNoTrace() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let url = directory.file("ledger.sqlite")
        let stores = try LedgerStores.open(at: url, kind: .phone, now: { EventBuilders.start }, newID: { UUID() })
        try await Self.seed(stores)
        var active = stores.programs.observeActive().makeAsyncIterator()
        let first = await active.next()
        #expect(first??.name == Self.programName)

        try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        let cleared = await active.next()
        #expect(cleared.map { $0 == nil } == true, "the open observation heard the erase")

        let left = try Self.traces(at: url)
        #expect(left.isEmpty, "still on disk: \(left)")
        let integrity = try await stores.queue.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
        #expect(integrity == "ok")
        let dangling = try await stores.queue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check").count }
        #expect(dangling == 0, "\(dangling) dangling references")
        let settings = try await stores.settings.load() == DataResetContract.restored
        #expect(settings)
    }
}

extension DataResetAdversarialTests {
    /// "table.column" for each cell, of every table in `sqlite_master`, whose text or blob holds one of `names`.
    static func cellsHolding(_ names: [String], in queue: DatabaseQueue) async throws -> [String] {
        try await queue.read { database in
            let tables = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            )
            var found: [String] = []
            for table in tables {
                for row in try Row.fetchAll(database, sql: "SELECT * FROM \(table)") {
                    for (column, value) in row {
                        let bytes: Data? = switch value.storage {
                        case let .string(string): Data(string.utf8)
                        case let .blob(data): data
                        default: nil
                        }
                        if let bytes, names.contains(where: { bytes.range(of: Data($0.utf8)) != nil }) {
                            found.append("\(table).\(column)")
                        }
                    }
                }
            }
            return found
        }
    }
}

/// Cancels the task it is given when the database next commits: what the app's gate does to Settings' task,
/// minus the frame SwiftUI takes.
private final class CancelOnCommit: TransactionObserver, Sendable {
    let task = Mutex<Task<Void, any Error>?>(nil)

    func observes(eventsOfKind _: DatabaseEventKind) -> Bool {
        true
    }

    func databaseDidChange(with _: DatabaseEvent) {}

    func databaseDidCommit(_: Database) {
        task.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    func databaseDidRollback(_: Database) {}
}
