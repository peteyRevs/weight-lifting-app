import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Round 3's reference model of `GRDBWorkoutEventStore` holding unreadable rows, as plain values: the
/// protocol's doc comments plus fix round 2's repair (SF2) and clock recovery (SF3).
struct RepairModel {
    typealias Contract = WorkoutEventStoreContract

    struct Row {
        var envelope: EventEnvelope
        var readable: Bool
    }

    struct Key: Hashable {
        let workout: WorkoutID
        let device: DeviceID
        let seq: UInt64
    }

    static let workouts = [Contract.workout, Contract.other, ClockRecoveryAdversarialTests.third]
    static let devices = [EventBuilders.phone, EventBuilders.watch]
    static let keys: [Key] = workouts.flatMap { workout in
        devices.flatMap { device in (1 ... 3).map { Key(workout: workout, device: device, seq: UInt64($0)) } }
    }

    /// Rows in row-id order: a repair keeps its row's place, an insert goes last.
    var rows: [Row] = []

    static func envelope(_ key: Key, stamp: Double) -> EventEnvelope {
        EventBuilders.envelope(
            .restSkipped, device: key.device, seq: key.seq, at: Contract.at(stamp), workoutID: key.workout
        )
    }

    static func key(_ envelope: EventEnvelope) -> Key {
        Key(workout: envelope.workoutID, device: envelope.device, seq: envelope.seq)
    }

    /// Mostly sub-millisecond finite stamps; sometimes NaN, ±∞ or ±1e300.
    static func stamp(using random: inout SeededGenerator) -> Double {
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0: .nan
        case 1: [.infinity, -.infinity, 1e300, -1e300].randomElement(using: &random) ?? 0
        default: Double.random(in: -1e5 ... 1e5, using: &random)
        }
    }

    /// One to five envelopes: copies of stored ones (readable or not), rivals of stored keys, and any key.
    func batch(using random: inout SeededGenerator) -> [EventEnvelope] {
        (0 ..< Int.random(in: 1 ... 5, using: &random)).map { _ in
            if let row = rows.randomElement(using: &random), Bool.random(using: &random) {
                let rival = Self.envelope(Self.key(row.envelope), stamp: Self.stamp(using: &random))
                return Bool.random(using: &random) ? row.envelope : rival
            }
            let key = Self.keys.randomElement(using: &random) ?? Self.keys[0]
            return Self.envelope(key, stamp: Self.stamp(using: &random))
        }
    }

    /// What `append` stores, or the first conflict, which leaves the model unchanged.
    mutating func append(_ batch: [EventEnvelope]) -> Result<[EventEnvelope], EngineError> {
        var next = rows
        var fresh: [EventEnvelope] = []
        for envelope in batch {
            if let index = next.firstIndex(where: { Self.key($0.envelope) == Self.key(envelope) }) {
                if next[index].readable {
                    guard next[index].envelope == envelope else {
                        return .failure(.conflictingEnvelope(envelope.key))
                    }
                    continue
                }
                next[index] = Row(envelope: envelope, readable: true)
            } else {
                next.append(Row(envelope: envelope, readable: true))
            }
            fresh.append(envelope)
        }
        rows = next
        return .success(fresh)
    }

    /// Every read of `store` against the model; an unreadable row's `wall_clock` is its original stamp.
    func check(_ store: GRDBWorkoutEventStore, _ context: String) async throws {
        for workout in Self.workouts {
            let mine = rows.filter { $0.envelope.workoutID == workout }
            let readable = mine.filter(\.readable).map(\.envelope)
            #expect(try await Self.same(store.envelopes(for: workout), readable), "\(context)")
            #expect(try await store.unreadableCount(for: workout) == mine.count { !$0.readable }, "\(context)")
            for device in Self.devices {
                let highest = mine.filter { $0.envelope.device == device }.map(\.envelope.seq).max()
                #expect(try await store.highestSeq(for: workout, device: device) == highest, "\(context)")
            }
        }
        #expect(try await Set(store.uncompactedWorkoutIDs()) == Set(rows.map(\.envelope.workoutID)), "\(context)")
        let newest = rows.map(\.envelope.wallClock).filter(\.timeIntervalSinceReferenceDate.isFinite).max()
        #expect(try await store.newestWallClock() == newest, "\(context)")
    }

    /// Equal envelopes, where two NaN stamps count as the same.
    static func same(_ lhs: [EventEnvelope], _ rhs: [EventEnvelope]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
            let (one, two) = (
                left.wallClock.timeIntervalSinceReferenceDate,
                right.wallClock.timeIntervalSinceReferenceDate
            )
            return left.event == right.event && left.workoutID == right.workoutID && left.key == right.key
                && (one == two || one.isNaN && two.isNaN)
        }
    }

    static func matches(
        _ actual: Result<[EventEnvelope], EngineError>,
        _ expected: Result<[EventEnvelope], EngineError>
    ) -> Bool {
        switch (actual, expected) {
        case let (.success(stored), .success(modelled)): same(stored, modelled)
        case let (.failure(thrown), .failure(modelled)): thrown == modelled
        default: false
        }
    }
}
