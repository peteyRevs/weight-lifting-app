import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Synchronization
import Testing

/// F07 S2 adversarial round 1: `LocalDevice` and `LedgerStores.open` (decision B4) under two connections opening one
/// file at once, rows of the other kind, ties, and repeated opens.
@Suite("Adversarial F07 S2 · LocalDevice", .tags(.persistence), .timeLimit(.minutes(1)))
struct LocalDeviceAdversarialTests {
    static func directory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "LocalDeviceAdversarial-\(ProcessInfo.processInfo.processIdentifier)-\(name)")
    }

    @Test(
        "Two connections opening a new file at once (an app and its extension) both open, on one device row",
        arguments: 0 ..< 10
    )
    func twoOpensAtOnce_oneRow(round: Int) throws {
        let folder = Self.directory("race\(round)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Database/ledger.sqlite")
        _ = try LedgerDatabase.open(at: url) // the file exists; only the device row is raced
        let results = Mutex<[Result<DeviceID, any Error>]>([])
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let result = Result {
                try LedgerStores.open(at: url, kind: .phone, now: { Date(timeIntervalSince1970: 0) }, newID: {
                    UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index)") ?? UUID()
                }).deviceID
            }
            results.withLock { $0.append(result) }
        }
        let ids = try results.withLock { try $0.map { try $0.get() } }
        #expect(Set(ids).count == 1, "both opens must agree on this device")
        let rows = try DatabaseQueue(path: url.path(percentEncoded: false)).read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM device WHERE kind = 'phone'")
        }
        #expect(rows == 1)
    }

    @Test("The other platform's rows are never this device, however many and however old")
    func otherKind_neverChosen() throws {
        let queue = try LedgerDatabase.inMemory()
        try queue.write { database in
            for number in 0 ..< 5 {
                try database.execute(
                    sql: "INSERT INTO device (id, kind, name, created_at) VALUES (?, 'watch', 'Apple Watch', ?)",
                    arguments: ["00000000-0000-4000-8000-0000000000A\(number)", "1990-01-0\(number + 1)T00:00:00Z"]
                )
            }
        }
        let phone = try LocalDevice.id(in: queue, kind: .phone, now: Date(), newID: {
            UUID(uuidString: "00000000-0000-4000-8000-0000000000FF") ?? UUID()
        })
        #expect(phone.rawValue.uuidString == "00000000-0000-4000-8000-0000000000FF")
        let again = try LocalDevice.id(in: queue, kind: .phone, now: Date(), newID: { UUID() })
        #expect(again == phone)
    }

    @Test("A lowercase stored id reads as the same device as its uppercase spelling, never a new row")
    func lowercaseID_isTheSameDevice() throws {
        let queue = try LedgerDatabase.inMemory()
        try queue.write { database in
            try database.execute(sql: """
            INSERT INTO device (id, kind, name, created_at)
            VALUES ('00000000-0000-4000-8000-0000000000ab', 'phone', 'iPhone', '2026-01-01T00:00:00Z')
            """)
        }
        let id = try LocalDevice.id(in: queue, kind: .phone, now: Date(), newID: { UUID() })
        #expect(id.rawValue.uuidString == "00000000-0000-4000-8000-0000000000AB")
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM device") } == 1)
    }
}
