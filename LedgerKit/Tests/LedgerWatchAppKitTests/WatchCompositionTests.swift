import Dependencies
import Foundation
import GRDB
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
@testable import LedgerWatchAppKit
import Testing

/// The watch composition on a real database file in a temporary directory (F07 criterion 2's data half: the watch
/// keeps its own database), decisions #28 and #29, the F05 inputs on settings and seeding, S1's `deviceID` input,
/// and the watch launch's order.
@Suite("WatchComposition", .timeLimit(.minutes(1)))
struct WatchCompositionTests {
    /// Reads the composition's database synchronously: GRDB's async read needs a `Sendable` value, and `Row` is not.
    static func read<Value>(_ stores: LedgerStores?, _ value: (Database) throws -> Value) throws -> Value {
        try #require(stores).queue.read(value)
    }

    /// Every row of the exercise table, as stored.
    static func exerciseRows(_ stores: LedgerStores?) throws -> [Row] {
        try read(stores) { try Row.fetchAll($0, sql: "SELECT * FROM exercise ORDER BY id") }
    }

    @Test("The watch launch opens the database in boot, then seeds, loads the settings and activates WatchConnectivity")
    func launch_runsTheStepsInOrder() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        #expect(harness.log == [.event(.began(.openDatabase))])
        await composition.resume(in: .active)
        #expect(harness.log == [
            .event(.began(.openDatabase)),
            .event(.began(.seedCatalog)),
            .event(.began(.loadSettings)),
            .event(.began(.activateCompanionSession)),
            .companionActivated
        ])
        harness.clearLog()
        await composition.resume(in: .active)
        #expect(harness.log.isEmpty)
    }

    @Test("Booting opens the database file at Database/ledger.sqlite, and the keys are bound to its stores")
    func boot_opensTheFile_andBindsTheStores() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        #expect(composition.state == .ready)
        #expect(FileManager.default.fileExists(atPath: harness.databasePath))
        await composition.resume(in: .active)
        #expect(composition.isCatalogSeeded)
        let count = try await withDependencies { composition.bind(&$0) } operation: {
            @Dependency(\.exerciseRepository) var exercises
            return try await exercises.all().count
        }
        #expect(count >= 200)
        #expect(try count == ExerciseCatalog.seed().count)
    }

    @Test("deviceID is bound to this device's row, never the nil UUID (S1 input)")
    func deviceID_isTheDeviceRow() throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        let bound = withDependencies { composition.bind(&$0) } operation: {
            @Dependency(\.deviceID) var deviceID
            return deviceID
        }
        #expect(bound == DeviceID(Harness.deviceUUID))
        #expect(bound.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        let stored = try Self.read(composition.stores) {
            try String.fetchAll($0, sql: "SELECT id FROM device WHERE kind = 'watch'")
        }
        #expect(stored == [Harness.deviceUUID.uuidString])
    }

    @Test("A second boot on the same file seeds nothing and keeps the device")
    func secondBoot_seedsNothing() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let first = harness.booted()
        await first.resume(in: .active)
        let seeded = try Self.exerciseRows(first.stores)
        let second = harness.booted(now: Harness.now.addingTimeInterval(86400)) // a rewrite would change updated_at
        await second.resume(in: .active)
        #expect(second.isCatalogSeeded)
        #expect(try Self.exerciseRows(second.stores) == seeded)
        #expect(second.stores?.deviceID == first.stores?.deviceID)
    }

    @Test("A settings row this app cannot read falls back to the defaults in memory and is left untouched")
    func unreadableSettings_fallBack_rowUntouched() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange { database in
            try database.execute(sql: "INSERT INTO settings VALUES ('singleton', 999, '{\"later\":true}', 'then')")
        }
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .ready)
        #expect(composition.settings == .default)
        #expect(harness.log.contains(.event(.failed(.loadSettings))))
        let row = try Self.read(composition.stores) {
            try Row.fetchOne($0, sql: "SELECT payload_version, payload, updated_at FROM settings")
        }
        #expect(row == ["payload_version": 999, "payload": "{\"later\":true}", "updated_at": "then"])
    }

    @Test("Saved settings are loaded")
    func savedSettings_areLoaded() async throws {
        let harness = Harness()
        defer { harness.remove() }
        var saved = Settings.default
        saved.autoRest.toggle()
        try await GRDBSettingsRepository(LedgerDatabase.open(at: harness.databaseURL)).save(saved)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.settings == saved)
    }

    @Test("In a process hosting tests, launch() boots nothing, and resume does nothing")
    func launch_whileTesting_bootsNothing() async {
        let composition = WatchComposition.launch()
        #expect(composition.state == .idle)
        #expect(composition.stores == nil)
        await composition.resume(in: .active)
        #expect(composition.state == .idle)
        #expect(!composition.isCatalogSeeded)
    }

    @Test("The live environment opens Application Support's file, or a fresh temporary one for a UI test")
    func liveEnvironment_databaseURL() {
        let live = WatchComposition.Environment.live(arguments: ["LedgerWatch"])
        #expect(live.databaseURL == LedgerStores.defaultURL)
        #expect(live.preparesDependencies)
        let first = WatchComposition.Environment.live(arguments: ["LedgerWatch", "-LEDGER_UITEST", "1"])
        let second = WatchComposition.Environment.live(arguments: ["LedgerWatch", "-LEDGER_UITEST", "1"])
        #expect(first.databaseURL.path().hasPrefix(URL.temporaryDirectory.path()))
        #expect(first.databaseURL != second.databaseURL)
        #expect(first.databaseURL.lastPathComponent == "ledger.sqlite")
    }

    @Test("Boots in the app and in a UI-tested app (-LEDGER_UITEST), never in a process hosting unit tests (S2-N1)")
    func boots_unlessHostingUnitTests() {
        #expect(WatchComposition.boots(arguments: ["LedgerWatch"], isTesting: false))
        #expect(!WatchComposition.boots(arguments: ["LedgerWatch"], isTesting: true))
        #expect(WatchComposition.boots(arguments: ["LedgerWatch", "-LEDGER_UITEST", "1"], isTesting: true))
    }
}
