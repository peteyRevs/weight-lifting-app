import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Criteria 7 and 8, and F04's store contract (`WorkoutEventStoreContract`, "Inputs from F04" item 3)
/// against the GRDB store, plus how it lays envelopes out in `workout_event`.
@Suite("GRDBWorkoutEventStore", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutEventStoreTests {
    typealias Contract = WorkoutEventStoreContract

    static let clock = EventBuilders.start

    static func store() throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        return (GRDBWorkoutEventStore(queue, now: { clock }), queue)
    }

    @Test("The GRDB store keeps the contract clause", arguments: WorkoutEventStoreContract.clauses)
    func contract_clauseHolds(_ clause: WorkoutEventStoreContract.Clause) async throws {
        let issue = try await clause.check(Self.store().0)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("The GRDB store keeps the storage clause", arguments: WorkoutEventStoreContract.storageClauses)
    func storageClause_holds(_ clause: WorkoutEventStoreContract.Clause) async throws {
        let issue = try await clause.check(Self.store().0)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("Criterion 7: a live log appended twice keeps each key once, and highestSeq is right per device")
    func appendTwice_keepsEachKeyOnce_highestSeqPerDevice() async throws {
        let (store, queue) = try Self.store()
        let phone = EventBuilders.log(from: [.restSkipped, .restSkipped], firstSeq: 2, startingAt: Contract.at(1))
        let watch = EventBuilders.log(from: [.restSkipped], device: EventBuilders.watch, firstSeq: 1)
        let log = [Contract.start(Contract.workout)] + phone + watch
        #expect(try await store.append(log) == log)
        #expect(try await store.append(log.reversed()).isEmpty)
        #expect(try await Set(store.envelopes(for: Contract.workout)) == Set(log))
        #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workout_event") } == 4)
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.phone) == 3)
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 1)
    }

    @Test("Criterion 8: compacting a workout deletes its rows and unlists it, and no other log")
    func compact_deletesRows_andUnlistsTheWorkout() async throws {
        let (store, queue) = try Self.store()
        _ = try await store.append([Contract.start(Contract.workout), Contract.skip(2), Contract.start(Contract.other)])
        try await store.compact(workout: Contract.workout)
        let rows = try await queue.read { try String.fetchAll($0, sql: "SELECT workout_id FROM workout_event") }
        #expect(rows == [ColumnCodec.text(Contract.other)])
        #expect(try await store.uncompactedWorkoutIDs() == [Contract.other])
    }

    @Test("A row: UUID text keys, the seq's bit pattern, the stamp as REAL (NULL when not finite), a v1 JSON blob")
    func append_writesTheDocumentedColumns() async throws {
        let (store, queue) = try Self.store()
        let finite = Contract.skip(.max, at: 10.493_826_8)
        let infinite = EventBuilders.envelope(
            .restSkipped, device: EventBuilders.watch, seq: 1, at: Date(timeIntervalSinceReferenceDate: .infinity)
        )
        _ = try await store.append([finite, infinite])
        let rows = try await queue.read { database in
            try Row.fetchAll(database, sql: """
            SELECT workout_id, device_id, seq, wall_clock, payload_version, typeof(payload) AS kind, payload,
                created_at
            FROM workout_event ORDER BY id
            """).map(StoredEvent.init)
        }
        try #require(rows.count == 2)
        let (first, second) = (rows[0], rows[1])
        #expect(first.workoutID == "00000000-0000-0000-0000-00000000F100")
        #expect(first.deviceID == ColumnCodec.text(EventBuilders.watch))
        #expect(first.seq == -1)
        #expect(first.wallClock == finite.wallClock.timeIntervalSinceReferenceDate)
        #expect(first.payloadVersion == 1)
        #expect(first.kind == "blob")
        #expect(try EnvelopeCodec.decode(first.payload, version: 1) == finite)
        #expect(first.createdAt == ColumnCodec.timestamp(Self.clock))
        #expect(second.wallClock == nil)
    }

    @Test("A stored envelope is judged decoded, not as bytes: the same envelope encoded otherwise is a duplicate")
    func append_comparesDecodedEnvelopes_notBytes() async throws {
        let (store, queue) = try Self.store()
        let envelope = Contract.start(Contract.workout)
        let unsorted = try JSONEncoder().encode(envelope)
        #expect(try unsorted != EnvelopeCodec.encode(envelope))
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO workout_event (workout_id, device_id, seq, wall_clock, payload_version, payload, created_at)
                VALUES (?, ?, 1, NULL, 1, ?, 'then')
                """,
                arguments: [ColumnCodec.text(Contract.workout), ColumnCodec.text(EventBuilders.phone), unsorted]
            )
        }
        #expect(try await store.append([envelope]).isEmpty)
    }

    @Test("The unique key refuses a second row for a key, whoever writes it")
    func uniqueKey_refusesASecondRow() async throws {
        let (store, queue) = try Self.store()
        _ = try await store.append([Contract.skip(1)])
        await #expect(throws: DatabaseError.self) {
            try await queue.write { database in
                try database.execute(sql: """
                INSERT INTO workout_event (workout_id, device_id, seq, payload_version, payload, created_at)
                SELECT workout_id, device_id, seq, payload_version, payload, created_at FROM workout_event
                """)
            }
        }
    }

    @Test(
        "Sub-millisecond stamps and payload dates read back exactly, and a re-append is a no-op",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func append_realStamps_readBackExactly(_ seed: PropertySeed) async throws {
        var random = seed.generator
        let seconds = (1 ... 4).map { _ in Double.random(in: 0 ..< 86400, using: &random) }
        let log = seconds.enumerated().map { index, stamp in
            Contract.logged(set: index, doneAt: stamp - 0.25, seq: UInt64(index) + 1, stamp: stamp)
        }
        let (store, _) = try Self.store()
        #expect(try await store.append(log) == log)
        #expect(try await store.append(log).isEmpty)
        #expect(try await store.envelopes(for: Contract.workout) == log)
    }
}

/// A `workout_event` row as stored.
private struct StoredEvent: Sendable {
    let workoutID: String
    let deviceID: String
    let seq: Int64
    let wallClock: Double?
    let payloadVersion: Int
    let kind: String
    let payload: Data
    let createdAt: String

    init(_ row: Row) {
        workoutID = row["workout_id"]
        deviceID = row["device_id"]
        seq = row["seq"]
        wallClock = row["wall_clock"]
        payloadVersion = row["payload_version"]
        kind = row["kind"]
        payload = row["payload"]
        createdAt = row["created_at"]
    }
}
