import Dependencies
import Foundation
import GRDB
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
@testable import LedgerWatchAppKit
import Testing

/// What the watch launch does when a step fails: decision #28 (seeding fails: log, carry on, retry) and
/// decision #29 (the database cannot be opened: a static screen, the file untouched, retried on the foreground).
@Suite("WatchComposition · failed launch steps", .timeLimit(.minutes(1)))
struct WatchCompositionRecoveryTests {
    /// Reads the composition's database synchronously: GRDB's async read needs a `Sendable` value, and `Row` is not.
    static func read<Value>(_ stores: LedgerStores?, _ value: (Database) throws -> Value) throws -> Value {
        try #require(stores).queue.read(value)
    }

    /// Every row of the exercise table, as stored.
    static func exerciseRows(_ stores: LedgerStores?) throws -> [Row] {
        try read(stores) { try Row.fetchAll($0, sql: "SELECT * FROM exercise ORDER BY id") }
    }

    @Test("Decision #28: a failed seed is logged, the launch carries on, and the next foreground seeds")
    func seedingFailure_carriesOn_thenRetries() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange { database in
            try database.execute(sql: """
            CREATE TRIGGER refuse_exercise BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'disk is full'); END
            """)
        }
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .ready)
        #expect(!composition.isCatalogSeeded)
        #expect(harness.log.contains(.event(.failed(.seedCatalog))))
        #expect(harness.log.suffix(3) == [
            .event(.began(.loadSettings)), .event(.began(.activateCompanionSession)), .companionActivated
        ])
        #expect(try Self.exerciseRows(composition.stores).isEmpty)

        try await #require(composition.stores).queue.write { try $0.execute(sql: "DROP TRIGGER refuse_exercise") }
        harness.clearLog()
        await composition.resume(in: .background)
        #expect(harness.log.isEmpty) // retried on return to the foreground only
        await composition.resume(in: .active)
        #expect(harness.log == [.event(.began(.seedCatalog))])
        #expect(composition.isCatalogSeeded)
        #expect(try Self.exerciseRows(composition.stores).count >= 200)
    }

    @Test("Decision #29: a file that cannot be opened shows the unavailable state and is never touched")
    func openFailure_isUnavailable_andTheFileIsUntouched() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let damaged = Data(repeating: 0x41, count: 4096)
        try FileManager.default.createDirectory(
            at: harness.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try damaged.write(to: harness.databaseURL)
        let listing = try FileManager.default
            .contentsOfDirectory(atPath: harness.databaseURL.deletingLastPathComponent().path)

        let composition = harness.booted()
        #expect(composition.state == .databaseUnavailable)
        #expect(harness.log.last == .event(.failed(.openDatabase)))
        await composition.resume(in: .active) // the first call is the launch's, not a retry
        await composition.resume(in: .background)
        #expect(composition.state == .databaseUnavailable)
        #expect(!harness.log.contains(.event(.began(.seedCatalog))))
        await composition.resume(in: .active) // a retry, which fails again
        #expect(harness.log.filter { $0 == .event(.failed(.openDatabase)) }.count == 2)
        #expect(try Data(contentsOf: harness.databaseURL) == damaged)
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: harness.databaseURL.deletingLastPathComponent().path) == listing)
        let unbound = withDependencies {
            $0.deviceID = DeviceID(UUID())
            composition.bind(&$0)
        } operation: {
            @Dependency(\.deviceID) var deviceID
            return deviceID.rawValue
        }
        #expect(unbound != Harness.deviceUUID) // nothing to bind until the database opens
    }

    @Test("Decision #29: once the file can be opened, the next foreground opens it, binds and seeds")
    func openFailure_retriedOnForeground() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try FileManager.default.createDirectory(at: harness.databaseURL, withIntermediateDirectories: true)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .databaseUnavailable)
        try FileManager.default.removeItem(at: harness.databaseURL) // the test, standing in for the cause going away
        harness.clearLog()
        await composition.resume(in: .active)
        #expect(composition.state == .ready)
        #expect(composition.isCatalogSeeded)
        #expect(harness.log == [
            .event(.began(.openDatabase)), .event(.began(.seedCatalog)), .event(.began(.loadSettings))
        ])
    }
}
