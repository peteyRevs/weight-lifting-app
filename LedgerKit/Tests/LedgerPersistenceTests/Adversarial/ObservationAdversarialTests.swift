import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization
import Testing

/// F05 S1 adversarial round 1: the `ValueObservation` → `AsyncStream` bridge (initial value, cancellation
/// by the consumer's task or by dropping the stream, no leak) and `GRDBSettingsRepository` beyond its suite.
@Suite("Adversarial S1 · observation and settings", .tags(.persistence), .timeLimit(.minutes(1)))
struct ObservationAdversarialTests {
    /// Counts the observation's fetches; its `Canary` is held only by the observation.
    final class Probe: Sendable {
        let fetches = Mutex(0)
    }

    final class Canary: Sendable {}

    /// A stream of the `device` row count, whose fetch closure alone holds a canary.
    static func deviceCount(_ queue: DatabaseQueue, _ probe: Probe) -> (AsyncStream<Int>, () -> Bool) {
        let canary = Canary()
        let stream = ValueObservation.tracking { [canary] database in
            withExtendedLifetime(canary) { probe.fetches.withLock { $0 += 1 } }
            return try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM device") ?? -1
        }.stream(in: queue)
        return (stream, { [weak canary] in canary != nil })
    }

    static func insertDevice(_ queue: DatabaseQueue, _ id: String) async throws {
        try await queue.write { database in
            try database.execute(
                sql: "INSERT INTO device (id, kind, name, created_at) VALUES (?, 'watch', 'W', 'then')",
                arguments: [id]
            )
        }
    }

    /// After the observer's asynchronous removal (queued on the writer), writes must fetch nothing.
    static func expectNoFetches(after queue: DatabaseQueue, _ probe: Probe) async throws {
        try await queue.write { _ in } // barrier: GRDB removes a cancelled observer on the writer
        let settled = probe.fetches.withLock { $0 }
        for index in 0 ..< 3 {
            try await insertDevice(queue, "after-\(index)")
        }
        try await queue.write { _ in }
        #expect(probe.fetches.withLock { $0 } == settled, "a cancelled observation kept fetching")
    }

    @Test("The stream emits the current value first, then a change, then stops when the consumer is cancelled")
    func cancellingTheConsumer_stopsTheObservation_andFreesIt() async throws {
        let queue = try LedgerDatabase.inMemory()
        try await Self.insertDevice(queue, "before")
        let probe = Probe()
        let (stream, isAlive) = Self.deviceCount(queue, probe)
        let (seen, seenContinuation) = AsyncStream.makeStream(of: Int.self)
        let consumer = Task {
            for await count in stream {
                seenContinuation.yield(count)
            }
            seenContinuation.finish()
        }
        var values = seen.makeAsyncIterator()
        #expect(await values.next() == 1)
        try await Self.insertDevice(queue, "during")
        #expect(await values.next() == 2)
        consumer.cancel()
        await consumer.value
        try await Self.expectNoFetches(after: queue, probe)
        #expect(!isAlive(), "the observation still holds its fetch closure")
        #expect(await values.next() == nil)
    }

    @Test("Dropping a stream, iterated or never iterated, stops its observation and frees it")
    func droppingTheStream_stopsTheObservation_andFreesIt() async throws {
        let queue = try LedgerDatabase.inMemory()
        let probe = Probe()
        let iteratedIsAlive: () -> Bool = try await {
            let (stream, isAlive) = Self.deviceCount(queue, probe)
            var iterator = stream.makeAsyncIterator()
            #expect(await iterator.next() == 0)
            try await Self.insertDevice(queue, "while-iterated")
            #expect(await iterator.next() == 1)
            return isAlive
        }()
        // Never iterated: dropped at once. Its start may still be queued, so only its fetches are checked.
        _ = Self.deviceCount(queue, probe)
        try await Self.expectNoFetches(after: queue, probe)
        #expect(!iteratedIsAlive(), "a dropped stream's observation lives on")
    }

    // MARK: Settings

    /// Every field away from the defaults, with exact weights no `Double` holds.
    static let exotic = Settings(
        units: .kg,
        defaultRest: RestDuration(seconds: 300) ?? .defaultRest,
        plateMathEnabled: false,
        autoRest: false,
        watchBuzz: false,
        weekStart: .saturday,
        plateInventory: [
            .kg: PlateInventory(
                bar: .kilograms(Decimal(sign: .plus, exponent: -7, significand: 150_000_001)),
                plates: []
            ),
            .lb: PlateInventory(
                bar: .pounds(Decimal(1) / 3),
                plates: [.pounds(Decimal(sign: .plus, exponent: -2, significand: 1))]
            )
        ]
    )

    @Test("Settings round-trip exactly through a second repository on the same queue")
    func settings_roundTripExactly_acrossRepositories() async throws {
        let queue = try LedgerDatabase.inMemory()
        try await GRDBSettingsRepository(queue).save(Self.exotic)
        let loaded = try await GRDBSettingsRepository(queue).load()
        #expect(loaded == Self.exotic)
        #expect(loaded.plateInventory[.lb]?.bar.grams == Self.exotic.plateInventory[.lb]?.bar.grams)
    }

    @Test("observe emits a change written by anyone, and the defaults once the row is gone")
    func observe_emitsForeignWrites_andDefaultsAfterDelete() async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue)
        var values = repository.observe().makeAsyncIterator()
        #expect(await values.next() == .default)
        try await GRDBSettingsRepository(queue).save(Self.exotic)
        #expect(await values.next() == Self.exotic)
        try await queue.write { try $0.execute(sql: "DELETE FROM settings") }
        #expect(await values.next() == .default)
    }
}
