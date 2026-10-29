import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F14 S1, N3, and F14-S1-5 and F14-S1a-R1-3 (ruled): a new install's settings start from the region, written in the
/// one write that inserts this device's row, so a first launch that ends at any point leaves both rows or neither.
/// An install that already has its device row (one made before F14 among them) is never seeded; the watch's launch
/// seeds nothing.
extension DatabaseLaunchTests {
    nonisolated static let refuseSettings =
        "CREATE TRIGGER refuse_settings BEFORE INSERT ON settings BEGIN SELECT RAISE(ABORT, 'full'); END"

    /// The number of rows of `table` in the launch's database.
    static func rows(_ table: String, _ launch: DatabaseLaunch) async throws -> Int? {
        try await #require(launch.stores).queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") }
    }

    @Test("F14 N3. A new install's first launch seeds the regional settings, and loads them; a later launch seeds none")
    func regional_seededOnce_thenLoaded() async throws {
        let subject = Subject(regionalSettings: Self.kilograms)
        defer { subject.remove() }
        subject.launch.open()
        await subject.launch.resume(isForeground: true)
        #expect(subject.events == [.began(.openDatabase), .began(.seedCatalog), .began(.loadSettings)])
        let loadsTheRegion = subject.launch.settings == Self.kilograms
        #expect(loadsTheRegion)
        var changed = Self.kilograms
        changed.weekStart = .wednesday
        let stores = try #require(subject.launch.stores)
        try await stores.settings.save(changed)
        let next = Subject(regionalSettings: Self.kilograms, in: subject.directory)
        next.launch.open()
        await next.launch.resume(isForeground: true)
        let keepsTheSaved = next.launch.settings == changed
        #expect(keepsTheSaved, "a second launch seeds nothing over the saved settings")
    }

    @Test("F14 N3. A launch given no regional settings (the watch) seeds nothing: the settings stay unstored")
    func noRegional_seedsNothing() async throws {
        let subject = Subject()
        defer { subject.remove() }
        subject.launch.open()
        await subject.launch.resume(isForeground: true)
        let loadsTheDefaults = subject.launch.settings == .default
        #expect(loadsTheDefaults)
        #expect(try await Self.rows("settings", subject.launch) == 0)
    }

    @Test("F14-S1-5. A database whose device row is there and whose settings row is not is not a new install: no seed")
    func deviceRowWithoutSettings_isNotSeeded() async throws {
        let subject = Subject(regionalSettings: Self.kilograms)
        defer { subject.remove() }
        try subject.arrange { database in
            try database.execute(
                sql: "INSERT INTO device (id, kind, name, created_at) VALUES (?, 'phone', 'iPhone', 'then')",
                arguments: [UUID().uuidString]
            )
        }
        subject.launch.open()
        await subject.launch.resume(isForeground: true)
        let loadsTheDefaults = subject.launch.settings == .default
        #expect(loadsTheDefaults)
        #expect(try await Self.rows("settings", subject.launch) == 0, "nothing was written: the install keeps its own")
    }

    /// The case R1-3 found: a first launch that ended after inserting the device row and before seeding would have
    /// left an install that is never seeded. The seed is now in the insert's write, so that state cannot be reached:
    /// a seed the database refuses takes the device row with it, the open fails (decision #29's screen), and the
    /// next open is a new install's, which seeds.
    @Test(
        "F14-S1a-R1-3. The device row and the seed are written together or not at all; a failed first open retries both"
    )
    func deviceRowAndSeed_areOneWrite() async throws {
        let subject = Subject(regionalSettings: Self.kilograms)
        defer { subject.remove() }
        try subject.arrange { try $0.execute(sql: Self.refuseSettings) }
        subject.launch.open()
        #expect(subject.launch.state == .databaseUnavailable)
        let left = try DatabaseQueue(path: subject.url.path(percentEncoded: false))
        let deviceRows = try await left.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM device") }
        try await left.write { try $0.execute(sql: "DROP TRIGGER refuse_settings") }
        try left.close()
        #expect(deviceRows == 0, "the refused seed took the device row with it")
        await subject.launch.resume(isForeground: true) // the first pass: no retry yet
        await subject.launch.resume(isForeground: true) // the foreground retries the open
        #expect(subject.launch.state == .ready)
        #expect(try await Self.rows("device", subject.launch) == 1)
        let seeded = subject.launch.settings == Self.kilograms
        #expect(seeded, "the retried open was a new install's, and seeded")
    }
}
