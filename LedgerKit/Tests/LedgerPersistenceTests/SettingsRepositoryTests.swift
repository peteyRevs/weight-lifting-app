import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBSettingsRepository`: the single settings row, and the `ValueObservation` bridge behind `observe()`.
@Suite("GRDBSettingsRepository", .tags(.persistence), .timeLimit(.minutes(1)))
struct SettingsRepositoryTests {
    static let clock = EventBuilders.start

    /// Every field away from `Settings.default`, with inventories that need exact weights.
    static let custom = Settings(
        units: .kg,
        defaultRest: RestDuration(seconds: 120) ?? .defaultRest,
        plateMathEnabled: false,
        autoRest: false,
        watchBuzz: false,
        weekStart: .sunday,
        plateInventory: [
            .kg: PlateInventory(bar: .kilograms(15), plates: [.kilograms(25), .kilograms(0.5)]),
            .lb: PlateInventory(bar: .pounds(35), plates: [.pounds(45), .pounds(1.25)])
        ]
    )

    static func repository() throws -> (GRDBSettingsRepository, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        return (GRDBSettingsRepository(queue, now: { clock }), queue)
    }

    @Test("Before the first save, load returns the defaults")
    func load_beforeAnySave_returnsDefaults() async throws {
        let (repository, _) = try Self.repository()
        #expect(try await repository.load() == .default)
    }

    @Test("Saved settings load back equal, in one row stamped by the injected clock")
    func save_thenLoad_roundTrips_inOneRow() async throws {
        let (repository, queue) = try Self.repository()
        try await repository.save(.default)
        try await repository.save(Self.custom)
        #expect(try await repository.load() == Self.custom)
        let rows = try await queue.read { database in
            try Row.fetchAll(database, sql: "SELECT id, updated_at, typeof(payload) FROM settings").map { row in
                [row[0], row[1], row[2]] as [String]
            }
        }
        #expect(rows == [["singleton", ColumnCodec.timestamp(Self.clock), "text"]])
    }

    @Test("observe emits the current settings, then each saved change")
    func observe_emitsCurrent_thenEachChange() async throws {
        let (repository, _) = try Self.repository()
        var values = repository.observe().makeAsyncIterator()
        #expect(await values.next() == .default)
        try await repository.save(Self.custom)
        #expect(await values.next() == Self.custom)
        var changed = Self.custom
        changed.weekStart = .monday
        try await repository.save(changed)
        #expect(await values.next() == changed)
    }

    @Test("An unreadable row fails load, and ends observe's stream instead of emitting")
    func unreadableRow_failsLoad_andEndsTheStream() async throws {
        let (repository, queue) = try Self.repository()
        try await queue.write { database in
            try database
                .execute(sql: "INSERT INTO settings (id, payload, updated_at) VALUES ('singleton', '{}', 'then')")
        }
        await #expect(throws: DecodingError.self) { try await repository.load() }
        var emitted: [Settings] = []
        for await settings in repository.observe() {
            emitted.append(settings)
        }
        #expect(emitted.isEmpty)
    }
}
