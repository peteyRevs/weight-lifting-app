import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F07 S1 adversarial round 1: LedgerFakes' settings repository and event store against the GRDB ones over
/// seeded random scripts: settings saved in turn load back alike; appends (duplicates, rivals, seqs across 2^63,
/// every event kind) and compactions give the same results, logs, seqs, listings and newest stamp.
@Suite(
    "Adversarial F07 S1 · settings and event fakes against GRDB",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct FakesStoreDifferentialAdversarialTests {
    typealias Model = EventStoreModelAdversarialTests

    static let seeds = Array(PropertySeed.all.prefix(60))

    /// Settings with every field random; the inventory built through its `init`, so normalised.
    static func settings(using random: inout SeededGenerator) -> Settings {
        let plates = (0 ..< Int.random(in: 0 ... 5, using: &random)).map { _ in
            Weight.pounds(Decimal(Int.random(in: -1 ... 90, using: &random)) / 2)
        }
        let bar = Weight.pounds(Decimal(Int.random(in: 0 ... 60, using: &random)))
        return Settings(
            units: Bool.random(using: &random) ? .lb : .kg,
            defaultRest: RestDuration(seconds: 30 + 15 * Int.random(in: 0 ... 18, using: &random)) ?? .defaultRest,
            plateMathEnabled: Bool.random(using: &random),
            autoRest: Bool.random(using: &random),
            watchBuzz: Bool.random(using: &random),
            weekStart: Weekday.allCases[Int.random(in: 0 ..< 7, using: &random)],
            plateInventory: Bool.random(using: &random) ? [:] : [.lb: PlateInventory(bar: bar, plates: plates)]
        )
    }

    @Test("Random settings saved in turn load back as GRDB's do", arguments: seeds)
    func settings_fakeMatchesGRDB(seed: PropertySeed) async throws {
        var random = seed.generator
        let stored = try GRDBSettingsRepository(LedgerDatabase.inMemory())
        let fake = InMemorySettingsRepository()
        for _ in 0 ..< 6 {
            let settings = Self.settings(using: &random)
            try await stored.save(settings)
            try await fake.save(settings)
            #expect(try await stored.load() == fake.load(), "\(seed)")
        }
    }

    /// A batch of up to five envelopes: `restSkipped` with random keys and rival stamps, or any event kind.
    static func batch(using random: inout SeededGenerator) -> [EventEnvelope] {
        (0 ..< Int.random(in: 0 ... 5, using: &random)).map { _ in
            guard Int.random(in: 0 ..< 3, using: &random) == 0 else {
                return Model.envelope(using: &random)
            }
            return EventBuilders.envelope(
                Model.event(using: &random),
                device: EventBuilders.watch,
                seq: UInt64(Int.random(in: 1 ... 3, using: &random)),
                at: WorkoutEventStoreContract.at(Double(Int.random(in: -5 ... 5, using: &random))),
                workoutID: Model.workouts[0]
            )
        }
    }

    static func result(_ body: () async throws -> [EventEnvelope]) async -> String {
        do {
            return try await "ok \(body())"
        } catch {
            return "threw \(error)"
        }
    }

    /// Everything a host reads back from the store, spelled for comparison.
    static func observables(_ store: any WorkoutEventStore) async throws -> [String] {
        var lines = try await [
            "uncompacted \(store.uncompactedWorkoutIDs().map(\.rawValue.uuidString).sorted())",
            "newest \(String(describing: store.newestWallClock()))"
        ]
        for workout in Model.workouts {
            try await lines.append("\(workout) log \(Set(store.envelopes(for: workout)).count)")
            try await lines.append("\(workout) unreadable \(store.unreadableCount(for: workout))")
            for device in Model.devices {
                try await lines
                    .append(
                        "\(workout) \(device) \(String(describing: store.highestSeq(for: workout, device: device)))"
                    )
            }
        }
        return lines
    }

    @Test("Random appends and compactions: the fake's results and logs match GRDB's", arguments: seeds)
    func events_fakeMatchesGRDB(seed: PropertySeed) async throws {
        var random = seed.generator
        let stored = try GRDBWorkoutEventStore(LedgerDatabase.inMemory(), now: { EventBuilders.start })
        let fake = InMemoryWorkoutEventStore()
        for step in 0 ..< 25 {
            if Int.random(in: 0 ..< 6, using: &random) == 0 {
                let workout = Model.workouts[Int.random(in: 0 ..< Model.workouts.count, using: &random)]
                try await stored.compact(workout: workout)
                await fake.compact(workout: workout)
            } else {
                let batch = Self.batch(using: &random)
                let storedOutcome = await Self.result { try await stored.append(batch) }
                let fakeOutcome = await Self.result { try await fake.append(batch) }
                #expect(storedOutcome == fakeOutcome, "\(seed), step \(step)")
            }
            #expect(try await Self.observables(stored) == Self.observables(fake), "\(seed), step \(step)")
            for workout in Model.workouts {
                #expect(try await Set(stored.envelopes(for: workout)) == Set(fake.envelopes(for: workout)), "\(seed)")
            }
        }
    }
}
