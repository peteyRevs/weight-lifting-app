import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Orchestrator decision (2026-09-30), test findings 1: a `workout_event` row this app version cannot read
/// (a later payload version, or damaged bytes) is left out of `envelopes(for:)`, kept in the table and
/// counted by `unreadableCount(for:)`; the readable envelopes of its log still read back.
@Suite("GRDBWorkoutEventStore · unreadable rows", .tags(.persistence), .timeLimit(.minutes(1)))
struct UnreadableEventRowTests {
    typealias Contract = WorkoutEventStoreContract

    /// A watch set logged at seq 3: the envelope whose row is made unreadable.
    static let hidden = Contract.logged(set: 0, doneAt: 3, seq: 3, stamp: 3)

    /// A store holding `start` and `skip(2)`, plus `hidden`'s key written as (`version`, `payload`).
    static func store(version: Int, payload: Data) async throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        let store = GRDBWorkoutEventStore(queue, now: { EventBuilders.start })
        _ = try await store.append([Contract.start(Contract.workout), Contract.skip(2)])
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO workout_event (workout_id, device_id, seq, wall_clock, payload_version, payload, created_at)
                VALUES (?, ?, 3, 3, ?, ?, 'then')
                """,
                arguments: [ColumnCodec.text(Contract.workout), ColumnCodec.text(EventBuilders.watch), version, payload]
            )
        }
        return (store, queue)
    }

    /// How a row can be unreadable: `hidden`'s own version-1 bytes marked as written by a later version,
    /// or damaged bytes marked version 1.
    struct Unreadable: Sendable, CustomStringConvertible {
        let description: String
        let version: Int
        let isDamaged: Bool

        func payload() throws -> Data {
            try isDamaged ? Data(#"{"event":"#.utf8) : EnvelopeCodec.encode(UnreadableEventRowTests.hidden)
        }
    }

    static let cases = [
        Unreadable(description: "a later payload version", version: 2, isDamaged: false),
        Unreadable(description: "damaged bytes", version: 1, isDamaged: true)
    ]

    @Test("An unreadable row is left out, counted and kept; the rest of its log still reads back", arguments: cases)
    func unreadableRow_isSkippedCountedAndKept(_ unreadable: Unreadable) async throws {
        let payload = try unreadable.payload()
        let (store, queue) = try await Self.store(version: unreadable.version, payload: payload)
        let readable = [Contract.start(Contract.workout), Contract.skip(2)]
        #expect(try await store.envelopes(for: Contract.workout) == readable)
        #expect(try await store.unreadableCount(for: Contract.workout) == 1)
        #expect(try await store.unreadableCount(for: Contract.other) == 0)
        // Its key is taken and its log stays listed; nothing but compaction deletes it.
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 3)
        #expect(try await store.uncompactedWorkoutIDs() == [Contract.workout])
        // A copy of it (or anything with its key) is skipped, and the stored row is left as it was.
        #expect(try await store.append([Self.hidden, Contract.skip(4)]) == [Contract.skip(4)])
        let kept = try await queue.read { database in
            try Row.fetchOne(database, sql: "SELECT payload_version, payload FROM workout_event WHERE seq = 3")
                .map { KeptRow(version: $0["payload_version"], payload: $0["payload"]) }
        }
        #expect(kept == KeptRow(version: unreadable.version, payload: payload))
        try await store.compact(workout: Contract.workout)
        #expect(try await store.unreadableCount(for: Contract.workout) == 0)
    }

    struct KeptRow: Equatable, Sendable {
        let version: Int
        let payload: Data
    }

    @Test("Decoding dispatches on the payload version: version 1 reads, any other is refused by name")
    func decode_dispatchesOnTheVersion() throws {
        let payload = try EnvelopeCodec.encode(Self.hidden)
        #expect(EnvelopeCodec.version == 1)
        #expect(try EnvelopeCodec.decode(payload, version: 1) == Self.hidden)
        for version in [0, 2, -1] {
            #expect(throws: LedgerPersistenceError.unknownPayloadVersion(version)) {
                try EnvelopeCodec.decode(payload, version: version)
            }
        }
    }
}
