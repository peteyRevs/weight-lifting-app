import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Synchronization
import Testing

/// `LocalDevice` (decision B4) and `LedgerStores.open`: this install's device row, inserted once per kind and read
/// back on every later launch.
@Suite("LocalDevice", .tags(.persistence), .timeLimit(.minutes(1)))
struct LocalDeviceTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// An id source that hands out `ids` in order and records how many it gave.
    final class IDSource: Sendable {
        private let ids: [UUID]
        private let given = Mutex(0)

        init(_ ids: [UUID]) {
            self.ids = ids
        }

        var count: Int {
            given.withLock { $0 }
        }

        func next() -> UUID {
            given.withLock { given in
                defer { given += 1 }
                return ids[given]
            }
        }
    }

    static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value)) ?? UUID()
    }

    @Test(
        "The first read inserts one row of the kind; every later read returns it",
        arguments: LocalDevice.Kind.allCases
    )
    func insertsOnce_thenReadsBack(kind: LocalDevice.Kind) throws {
        let queue = try LedgerDatabase.inMemory()
        let source = IDSource([Self.uuid(1), Self.uuid(2)])
        let first = try LocalDevice.id(in: queue, kind: kind, now: Self.now, newID: source.next)
        let second = try LocalDevice.id(in: queue, kind: kind, now: Self.now.addingTimeInterval(60), newID: source.next)
        #expect(first == DeviceID(Self.uuid(1)))
        #expect(second == first)
        #expect(source.count == 1)
        let rows = try queue.read { try Row.fetchAll($0, sql: "SELECT id, kind, name, created_at FROM device") }
        #expect(rows.count == 1)
        #expect(rows.first?["kind"] == kind.rawValue)
        #expect(rows.first?["name"] == kind.name)
        #expect(rows.first?["created_at"] == ColumnCodec.timestamp(Self.now))
    }

    @Test("A row of the other kind (the paired device's) is never this device's")
    func otherKind_isNotThisDevice() throws {
        let queue = try LedgerDatabase.inMemory()
        let source = IDSource([Self.uuid(1), Self.uuid(2)])
        let watch = try LocalDevice.id(in: queue, kind: .watch, now: Self.now, newID: source.next)
        let phone = try LocalDevice.id(in: queue, kind: .phone, now: Self.now, newID: source.next)
        #expect(watch == DeviceID(Self.uuid(1)))
        #expect(phone == DeviceID(Self.uuid(2)))
        #expect(try LocalDevice.id(in: queue, kind: .watch, now: Self.now, newID: source.next) == watch)
    }

    @Test("Of two rows of one kind, the oldest is this device's")
    func twoRows_oldestWins() throws {
        let queue = try LedgerDatabase.inMemory()
        try queue.write { database in
            for (id, createdAt) in [
                (Self.uuid(7), "2026-02-01T00:00:00.000Z"),
                (Self.uuid(8), "2026-01-01T00:00:00.000Z")
            ] {
                try database.execute(
                    sql: "INSERT INTO device (id, kind, name, created_at) VALUES (?, 'phone', 'iPhone', ?)",
                    arguments: [id.uuidString, createdAt]
                )
            }
        }
        let source = IDSource([])
        #expect(try LocalDevice
            .id(in: queue, kind: .phone, now: Self.now, newID: source.next) == DeviceID(Self.uuid(8)))
    }

    @Test("A stored id that is not a UUID throws malformedIdentifier and stays as it was")
    func malformedID_throws_andKeepsTheRow() throws {
        let queue = try LedgerDatabase.inMemory()
        try queue.write { database in
            try database
                .execute(sql: "INSERT INTO device (id, kind, name, created_at) VALUES ('nope', 'watch', 'W', 'x')")
        }
        let source = IDSource([Self.uuid(1)])
        #expect(throws: LedgerPersistenceError.malformedIdentifier("nope")) {
            try LocalDevice.id(in: queue, kind: .watch, now: Self.now, newID: source.next)
        }
        #expect(try queue.read { try String.fetchAll($0, sql: "SELECT id FROM device") } == ["nope"])
    }

    @Test("LedgerStores.open opens the file and keeps the device across opens")
    func storesOpen_keepsTheDevice() throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let url = directory.file("Database/ledger.sqlite")
        let source = IDSource([Self.uuid(1), Self.uuid(2)])
        let first = try LedgerStores.open(at: url, kind: .phone, now: { Self.now }, newID: source.next)
        let second = try LedgerStores.open(at: url, kind: .phone, now: { Self.now }, newID: source.next)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(first.deviceID == DeviceID(Self.uuid(1)))
        #expect(second.deviceID == first.deviceID)
        #expect(source.count == 1)
    }

    @Test("LedgerStores.seedCatalog seeds the bundled catalog once, at its version")
    func storesSeedCatalog_seedsOnce() async throws {
        let stores = try LedgerStores(LedgerDatabase.inMemory(), deviceID: DeviceID(Self.uuid(1)), now: { Self.now })
        try await stores.seedCatalog()
        let seeded = try await stores.exercises.all()
        try await stores.seedCatalog()
        #expect(try await stores.exercises.all() == seeded)
        #expect(try seeded.count == ExerciseCatalog.seed().count)
    }

    @Test("The default location is Application Support/Database/ledger.sqlite")
    func defaultURL_isItsOwnDirectory() {
        let expected = URL.applicationSupportDirectory.appending(path: "Database/ledger.sqlite")
        #expect(LedgerStores.defaultURL.path(percentEncoded: false) == expected.path(percentEncoded: false))
    }
}
