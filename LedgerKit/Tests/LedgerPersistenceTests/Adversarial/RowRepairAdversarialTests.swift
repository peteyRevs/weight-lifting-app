import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 3 (close-out): fix round 2's repair of an unreadable `workout_event` row (review
/// SF2, orchestrator decision 2026-09-30). The first readable envelope appended with the row's key overwrites
/// the row in place and counts as new; a conflict anywhere in its batch rolls the repair back; a later version
/// and a damaged row are repaired alike; the repair is per workout and rewrites the row's `wall_clock`.
@Suite("Adversarial S1 round 3 · row repair", .tags(.persistence), .timeLimit(.minutes(1)))
struct RowRepairAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    /// Both families: versions this app does not know, and rows in a known version it cannot read.
    static let damages = [
        "payload_version = 2", "payload_version = 9223372036854775807", "payload_version = 1e30",
        "payload_version = x''", "payload_version = ''", "payload = substr(payload, 1, 10)", "payload = x'C0'",
        "payload = x'EDA080'", "payload = 7"
    ]

    static let log = [Contract.skip(1), Contract.skip(2), Contract.skip(3), Contract.skip(1, in: Contract.other)]

    /// `log` stored, then the row of `envelope`'s key changed by `change`.
    static func store(
        damaging envelope: EventEnvelope = Contract.skip(2),
        with change: String
    ) async throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        let store = GRDBWorkoutEventStore(queue, now: { EventBuilders.start })
        #expect(try await store.append(log) == log)
        try await damage(envelope, with: change, in: queue)
        return (store, queue)
    }

    static func damage(_ envelope: EventEnvelope, with change: String, in queue: DatabaseQueue) async throws {
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE workout_event SET \(change) WHERE workout_id = ? AND device_id = ? AND seq = ?",
                arguments: [
                    ColumnCodec.text(envelope.workoutID), ColumnCodec.text(envelope.device),
                    ColumnCodec.column(seq: envelope.seq)
                ]
            )
            #expect(database.changesCount == 1)
        }
    }

    /// Every row, every column quoted, in row-id order.
    static func dump(_ queue: DatabaseQueue) async throws -> [String] {
        try await PayloadVersionAdversarialTests.dump(queue)
    }

    @Test("A conflict on another key later in the batch rolls the repair back", arguments: damages)
    func repair_isRolledBack_byAConflictOnAnotherKey(_ damage: String) async throws {
        let (store, queue) = try await Self.store(with: damage)
        let before = try await Self.dump(queue)
        await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(3).key)) {
            try await store.append([Contract.skip(2), Contract.skip(4), Contract.extend(3)])
        }
        #expect(try await Self.dump(queue) == before)
        #expect(try await store.unreadableCount(for: Contract.workout) == 1)
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 3)
        #expect(try await store.append([Contract.skip(2)]) == [Contract.skip(2)])
        #expect(try await store.unreadableCount(for: Contract.workout) == 0)
    }

    @Test("Two envelopes for one unreadable key in a batch: a copy repairs once, a rival conflicts in either order")
    func twoEnvelopes_forOneUnreadableKey_inOneBatch() async throws {
        for damage in Self.damages {
            let (store, queue) = try await Self.store(with: damage)
            let before = try await Self.dump(queue)
            for batch in [[Contract.skip(2), Contract.extend(2)], [Contract.extend(2), Contract.skip(2)]] {
                await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(2).key), "\(damage)") {
                    try await store.append(batch)
                }
                #expect(try await Self.dump(queue) == before, "\(damage)")
            }
            let batch = [Contract.skip(2), Contract.skip(4), Contract.skip(2), Contract.skip(1)]
            #expect(try await store.append(batch) == [Contract.skip(2), Contract.skip(4)], "\(damage)")
            #expect(try await store.unreadableCount(for: Contract.workout) == 0, "\(damage)")
            let expected = [1, 2, 3, 4].map { Contract.skip($0) }
            #expect(try await store.envelopes(for: Contract.workout) == expected, "\(damage)")
        }
    }

    @Test("A later version and a damaged row are repaired alike: same row, version 1, the incoming bytes and stamp")
    func laterVersion_andDamagedRow_areRepairedInPlace() async throws {
        let winner = Contract.skip(2, at: 50) // a rival of the stored skip(2): the first readable one wins
        let stamp = ColumnCodec.finiteSeconds(Contract.at(99)) ?? 0
        for damage in ["payload_version = 7", "payload = x'7B7D'"] {
            let (store, queue) = try await Self.store(with: "\(damage), wall_clock = \(stamp)")
            #expect(try await store.newestWallClock() == Contract.at(99), "\(damage)")
            let idAndCreated = "SELECT id || created_at FROM workout_event WHERE seq = 2 AND workout_id = ?"
            let key: StatementArguments = [ColumnCodec.text(Contract.workout)]
            let identity = try await queue.read { try String.fetchOne($0, sql: idAndCreated, arguments: key) }
            #expect(try await store.append([winner]) == [winner], "\(damage)")
            let (version, payload, seconds) = try await queue.read { database in
                let row = try Row.fetchOne(database, sql: """
                SELECT payload_version, payload, wall_clock FROM workout_event WHERE seq = 2 AND workout_id = ?
                """, arguments: key)
                return (row?["payload_version"] as Int?, row?["payload"] as Data?, row?["wall_clock"] as Double?)
            }
            #expect(version == 1, "\(damage)")
            #expect(try payload == EnvelopeCodec.encode(winner), "\(damage)")
            #expect(seconds == ColumnCodec.finiteSeconds(Contract.at(50)), "\(damage)")
            #expect(try await queue.read { try String.fetchOne($0, sql: idAndCreated, arguments: key) } == identity)
            #expect(try await store.newestWallClock() == Contract.at(50), "\(damage)")
            #expect(try await store.envelopes(for: Contract.workout)[1] == winner, "\(damage)")
        }
    }

    @Test("A repair is per workout; one batch repairs rows in two workouts, in the order given")
    func repair_isPerWorkout_andOrdered() async throws {
        let (store, queue) = try await Self.store(with: "payload_version = 2")
        // The same device and seq in another workout is another key: it is inserted and repairs nothing.
        let elsewhere = Contract.skip(2, in: Contract.other)
        #expect(try await store.append([elsewhere]) == [elsewhere])
        #expect(try await store.unreadableCount(for: Contract.workout) == 1)
        try await Self.damage(Contract.skip(1, in: Contract.other), with: "payload = x'FFFE'", in: queue)
        #expect(try await store.unreadableCount(for: Contract.other) == 1)
        let batch = [Contract.skip(5), Contract.skip(1, in: Contract.other), Contract.skip(1), Contract.skip(2)]
        let stored = [Contract.skip(5), Contract.skip(1, in: Contract.other), Contract.skip(2)]
        #expect(try await store.append(batch) == stored)
        #expect(try await store.unreadableCount(for: Contract.workout) == 0)
        #expect(try await store.unreadableCount(for: Contract.other) == 0)
        #expect(try await store.envelopes(for: Contract.other) == [Contract.skip(1, in: Contract.other), elsewhere])
    }

    @Test("A repair by an envelope with a NaN stamp stores a NULL wall_clock, which the clock recovery skips")
    func repair_byANaNStamp_storesNull() async throws {
        let (store, queue) = try await Self.store(damaging: Contract.skip(3), with: "payload_version = 2")
        let nan = EventBuilders.envelope(.restSkipped, device: EventBuilders.watch, seq: 3, at: Contract.at(.nan))
        #expect(try await store.append([nan]).count == 1)
        #expect(try await store.unreadableCount(for: Contract.workout) == 0)
        let sql = "SELECT quote(wall_clock) FROM workout_event WHERE seq = 3"
        let clock = try await queue.read { try String.fetchOne($0, sql: sql) }
        #expect(clock == "NULL")
        #expect(try await store.newestWallClock() == Contract.at(2))
    }
}
