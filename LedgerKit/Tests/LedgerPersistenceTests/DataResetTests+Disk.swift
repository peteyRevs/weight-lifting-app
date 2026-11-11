import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F14 S3, N21 and N23 over GRDB: a cancelled erase is whole or absent, and the deleted rows leave the file and its
/// WAL.
extension DataResetTests {
    @Test("N23. An erase whose task is cancelled at once leaves everything or nothing, never a part")
    func cancelledErase_isWholeOrAbsent() async throws {
        let stores = try await Self.seededDatabase()
        let before = try await Self.rowCounts(stores.queue)
        let erase = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        }
        _ = await erase.result
        let after = try await Self.rowCounts(stores.queue)
        let catalog = try ExerciseCatalog.seed().count
        let kept = after == before
        let erased = after["workout"] == 0 && after["program"] == 0 && after["settings"] == 1
            && after["exercise"] == catalog
        #expect(kept || erased, "\(after)")
    }

    // MARK: N21: gone from the disk

    /// Whether the file at `url` holds `text`'s UTF-8 bytes; a missing file holds nothing.
    static func file(_ url: URL, holds text: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return false
        }
        return try Data(contentsOf: url).range(of: Data(text.utf8)) != nil
    }

    @Test("N21. After the erase, a custom exercise's and a workout's names are in neither the file nor its WAL")
    func erase_leavesNoTraceOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DataResetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ledger.sqlite", directoryHint: .notDirectory)
        let wal = directory.appending(path: "ledger.sqlite-wal", directoryHint: .notDirectory)
        let stores = try LedgerStores.open(at: url, kind: .phone, now: { EventBuilders.start }, newID: { UUID() })
        try await DataResetContract.seedHistory(Self.grdbStores(stores))
        let names = [DataResetContract.custom.name, DataResetContract.workout(1).name]
        for name in names {
            let held = try Self.file(url, holds: name) || Self.file(wal, holds: name)
            #expect(held, "\(name) was never written: the scan would prove nothing")
        }
        try await stores.reset.eraseAll(restoring: DataResetContract.restored)
        for name in names {
            #expect(try !Self.file(url, holds: name), "\(name) is still in the database file")
            #expect(try !Self.file(wal, holds: name), "\(name) is still in the WAL")
        }
        let reopened = try LedgerStores.open(at: url, kind: .phone, now: { EventBuilders.start }, newID: { UUID() })
        #expect(reopened.deviceID == stores.deviceID)
        let restored = try await reopened.settings.load() == DataResetContract.restored
        #expect(restored)
    }
}
