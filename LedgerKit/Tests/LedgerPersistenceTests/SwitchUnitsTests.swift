import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization
import Testing

/// F14 S2, criterion 1's program part and ruling A4: `SettingsRepository.switchUnits(_:)` saves the settings and
/// converts the active program's weights in one write, both or neither, over GRDB and over the linked in-memory
/// stores alike.
@Suite("SettingsRepository · switchUnits", .tags(.persistence), .timeLimit(.minutes(1)))
struct SwitchUnitsTests {
    /// The two kinds of store, each holding the bundled catalog, the spec's seed program (active, every start load
    /// in pounds) and the default settings in pounds.
    enum Kind: String, CaseIterable, Sendable {
        case grdb, inMemory
    }

    struct Stores {
        let settings: any SettingsRepository
        let programs: any ProgramRepository
        /// GRDB's queue, for the damage test; nil in memory.
        let queue: DatabaseQueue?
    }

    static func stores(_ kind: Kind) async throws -> Stores {
        let catalog = try ExerciseCatalog.seed()
        let program = try Fixtures.seedProgram()
        switch kind {
        case .grdb:
            let queue = try LedgerDatabase.inMemory()
            let exercises = GRDBExerciseRepository(queue)
            try await exercises.seedIfNeeded(catalog, version: ExerciseCatalog.version)
            let programs = GRDBProgramRepository(queue)
            try await programs.save(program)
            return Stores(settings: GRDBSettingsRepository(queue), programs: programs, queue: queue)
        case .inMemory:
            let stores = InMemoryStores(seed: InMemoryStores.Seed(catalog: catalog, programs: [program]))
            return Stores(settings: stores.settings, programs: stores.programs, queue: nil)
        }
    }

    /// The start load of the active program's slot `index` of its first day.
    static func load(_ stores: Stores, slot index: Int) async throws -> Weight? {
        let program = try #require(try await stores.programs.active())
        return try #require(program.days.first?.slots[index]).startLoad
    }

    static var kilograms: Settings {
        var settings = Settings.default
        settings.units = .kg
        return settings
    }

    @Test(
        "Pounds to kilograms: the settings are saved and each start load is on its equipment's kilogram grid",
        arguments: Kind.allCases
    )
    func switch_savesAndConverts(_ kind: Kind) async throws {
        let stores = try await Self.stores(kind)
        try await stores.settings.switchUnits(Self.kilograms)
        let saved = try await stores.settings.load()
        #expect(saved.units == .kg)
        // Bench 180 lb (barbell): 81.65 kg, 82.5. Incline DB 50 lb (dumbbell): 22.68 kg, 22.5.
        #expect(try await Self.load(stores, slot: 0) == .kilograms(82.5))
        #expect(try await Self.load(stores, slot: 1) == .kilograms(22.5))
    }

    @Test("Units already stored: only the settings are saved, and an off-grid load is kept", arguments: Kind.allCases)
    func sameUnits_convertNothing(_ kind: Kind) async throws {
        let stores = try await Self.stores(kind)
        try await stores.settings.switchUnits(Self.kilograms)
        let active = try #require(try await stores.programs.active())
        _ = try await stores.programs.update(active.id) { program in
            var changed = program
            changed.days[0].slots[0].startLoad = .kilograms(81.25)
            return changed
        }
        var rest = Self.kilograms
        rest.defaultRest = RestDuration(clampingSeconds: 120)
        try await stores.settings.switchUnits(rest)
        #expect(try await stores.settings.load().defaultRest.seconds == 120)
        #expect(try await Self.load(stores, slot: 0) == .kilograms(81.25))
    }

    @Test("With no active program, only the settings are saved", arguments: Kind.allCases)
    func noActiveProgram_savesTheSettings(_ kind: Kind) async throws {
        let stores = try await Self.stores(kind)
        let active = try #require(try await stores.programs.active())
        try await stores.programs.delete(active.id)
        try await stores.settings.switchUnits(Self.kilograms)
        #expect(try await stores.settings.load().units == .kg)
        #expect(try await stores.programs.active() == nil)
    }

    /// F14 S2 fix round 3 (ruled): a program this app cannot read never stops the lifter changing units (F05's rule).
    @Test("GRDB: an active program that cannot be read is left as it is, and the settings are switched")
    func unreadableProgram_isSkipped() async throws {
        let stores = try await Self.stores(.grdb)
        let queue = try #require(stores.queue)
        try await queue.write { try $0.execute(sql: "UPDATE slot SET sets = 99") }
        let slots = "SELECT quote(start_load_e7g) || ',' || sets FROM slot ORDER BY id"
        let before = try await queue.read { try String.fetchAll($0, sql: slots) }
        try await stores.settings.switchUnits(Self.kilograms)
        #expect(try await stores.settings.load().units == .kg)
        let after = try await queue.read { try String.fetchAll($0, sql: slots) }
        let untouched = after == before
        #expect(untouched)
    }

    @Test("GRDB: the settings row and the program's slots are written in one transaction")
    func grdb_oneTransaction() async throws {
        let stores = try await Self.stores(.grdb)
        let queue = try #require(stores.queue)
        let commits = Commits()
        queue.add(transactionObserver: commits, extent: .databaseLifetime)
        try await stores.settings.switchUnits(Self.kilograms)
        #expect(commits.count == 1)
        #expect(try await Self.load(stores, slot: 0) == .kilograms(82.5))
    }
}

/// Counts the commits of a database.
private final class Commits: TransactionObserver, Sendable {
    private let commits = Mutex(0)

    var count: Int {
        commits.withLock { $0 }
    }

    func observes(eventsOfKind _: DatabaseEventKind) -> Bool {
        true
    }

    func databaseDidChange(with _: DatabaseEvent) {}

    func databaseDidCommit(_: Database) {
        commits.withLock { $0 += 1 }
    }

    func databaseDidRollback(_: Database) {}
}
