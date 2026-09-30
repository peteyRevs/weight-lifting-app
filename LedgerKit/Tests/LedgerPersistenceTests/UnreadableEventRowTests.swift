import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Orchestrator decision (2026-09-30), test findings 1, amended by fix round 2 (review SF2 and SF3, close-out
/// finding 4 and review N4). A `workout_event` row this app version cannot read (a later payload version,
/// damaged bytes, or a column of the wrong kind) is left out of `envelopes(for:)`, counted by
/// `unreadableCount(for:)` and kept, never trapping. Its stamp still counts for `newestWallClock()`. The first
/// readable envelope appended with its key repairs it.
@Suite("GRDBWorkoutEventStore · unreadable rows", .tags(.persistence), .timeLimit(.minutes(1)))
struct UnreadableEventRowTests {
    typealias Contract = WorkoutEventStoreContract

    /// A watch set logged at seq 3: the envelope whose row is made unreadable. Its stamp is the log's newest.
    static let hidden = Contract.logged(set: 0, doneAt: 3, seq: 3, stamp: 3)
    /// A different envelope with `hidden`'s key.
    static let rival = Contract.logged(set: 1, doneAt: 3, seq: 3, stamp: 3)
    static let readable = [Contract.start(Contract.workout), Contract.skip(2)]

    /// How a row can be unreadable: SQL for its `payload_version` and `payload`, where `?` is `hidden`'s
    /// own version-1 bytes.
    struct Damage: Sendable, CustomStringConvertible {
        let description: String
        let version: String
        let payload: String
    }

    static let damages = [
        Damage(description: "a later payload version", version: "2", payload: "?"),
        Damage(description: "damaged bytes", version: "1", payload: #"CAST('{"event":' AS BLOB)"#),
        Damage(description: "a version stored as text", version: "'two'", payload: "?"),
        Damage(description: "a version stored as a blob", version: "x'01'", payload: "?"),
        Damage(description: "a payload stored as a number", version: "1", payload: "5"),
        Damage(description: "bytes that are not UTF-8", version: "1", payload: "x'FFFE00'")
    ]

    /// A store holding `readable`, plus `hidden`'s key written with `damage`.
    static func store(_ damage: Damage) async throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        let store = GRDBWorkoutEventStore(queue, now: { EventBuilders.start })
        _ = try await store.append(readable)
        let key: StatementArguments = [
            ColumnCodec.text(Contract.workout), ColumnCodec.text(EventBuilders.watch),
            ColumnCodec.finiteSeconds(hidden.wallClock)
        ]
        let arguments = try damage.payload.contains("?") ? key + [EnvelopeCodec.encode(hidden)] : key
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO workout_event (workout_id, device_id, seq, wall_clock, payload_version, payload, created_at)
                VALUES (?, ?, 3, ?, \(damage.version), \(damage.payload), 'then')
                """,
                arguments: arguments
            )
        }
        return (store, queue)
    }

    /// Row 3 as stored: its version and payload, quoted.
    static func row3(_ queue: DatabaseQueue) async throws -> String? {
        try await queue.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT quote(payload_version) || ',' || quote(payload) FROM workout_event WHERE seq = 3"
            )
        }
    }

    @Test(
        "An unreadable row is left out, counted and kept, never trapping; its key and stamp still count",
        arguments: damages
    )
    func unreadableRow_isLeftOutCountedAndKept(_ damage: Damage) async throws {
        let (store, queue) = try await Self.store(damage)
        let before = try await Self.row3(queue)
        #expect(try await store.envelopes(for: Contract.workout) == Self.readable)
        #expect(try await store.unreadableCount(for: Contract.workout) == 1)
        #expect(try await store.unreadableCount(for: Contract.other) == 0)
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 3)
        #expect(try await store.uncompactedWorkoutIDs() == [Contract.workout])
        // SF3: the clock restarts after the unreadable row's stamp, the newest here.
        #expect(try await store.newestWallClock() == Self.hidden.wallClock)
        #expect(try await Self.row3(queue) == before)
    }

    @Test(
        "A readable envelope with the key repairs the row and counts as new; a different one then conflicts",
        arguments: damages
    )
    func readableCopy_repairsTheRow(_ damage: Damage) async throws {
        let (store, queue) = try await Self.store(damage)
        #expect(try await store.append([Self.hidden, Contract.skip(4)]) == [Self.hidden, Contract.skip(4)])
        #expect(try await store.unreadableCount(for: Contract.workout) == 0)
        #expect(try await store.envelopes(for: Contract.workout) == Self.readable + [Self.hidden, Contract.skip(4)])
        let payload = try EnvelopeCodec.encode(Self.hidden)
        let repaired = try await queue.read { database in
            try Row.fetchOne(database, sql: "SELECT payload_version, payload FROM workout_event WHERE seq = 3")
                .map { KeptRow(version: $0["payload_version"], payload: $0["payload"]) }
        }
        #expect(repaired == KeptRow(version: 1, payload: payload))
        #expect(try await store.append([Self.hidden]).isEmpty)
        await #expect(throws: EngineError.conflictingEnvelope(Self.rival.key)) {
            try await store.append([Contract.skip(5), Self.rival])
        }
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 4)
    }

    @Test("A repair is part of its batch: a conflict later in the batch rolls it back", arguments: damages)
    func repair_inAConflictingBatch_rollsBack(_ damage: Damage) async throws {
        let (store, queue) = try await Self.store(damage)
        let before = try await Self.row3(queue)
        await #expect(throws: EngineError.conflictingEnvelope(Self.rival.key)) {
            try await store.append([Self.hidden, Self.rival])
        }
        #expect(try await Self.row3(queue) == before)
        #expect(try await store.unreadableCount(for: Contract.workout) == 1)
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
