import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 2 (close-out): `workout_event.payload_version` from the fix round. Every row is
/// written in version 1, and no writer may leave it out. A row this app cannot read (a later or unknown
/// version, a damaged version column, damaged bytes) is left out of its log in the log's order, counted per
/// workout, kept byte for byte, and its key stays taken; compaction deletes it with its log. Fix round 2
/// (review SF2, orchestrator decision): the first readable envelope appended with its key repairs it.
@Suite("Adversarial S1 round 2 · payload versions", .tags(.persistence), .timeLimit(.minutes(1)))
struct PayloadVersionAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    static let workouts = (0 ..< 3).map { WorkoutID(EventBuilders.uuid(0xF500 + $0)) }
    static let devices = [EventBuilders.phone, EventBuilders.watch]

    /// `SET` clauses that make a row unreadable. A version outside `Int32` is left out on a 32-bit `Int`
    /// (arm64_32 watches), where reading it traps (test findings, round 2).
    static let damages = [
        "payload_version = 2", "payload_version = 7", "payload_version = 0", "payload_version = -1",
        "payload_version = 'two'", "payload_version = x'01'",
        "payload = x''", "payload = x'FFFE00'", "payload = '[]'", "payload = 'null'", "payload = x'7B7D'",
        "payload = 5", "payload = 2.5", "payload = substr(payload, 1, length(payload) - 1)",
        #"payload = CAST(replace(CAST(payload AS TEXT), '"seq":', '"sequence":') AS BLOB)"#
    ] + (Int.bitWidth == 64 ? ["payload_version = 9223372036854775807", "payload_version = -9223372036854775808"]
        : [])

    /// `SET` clauses that leave a row readable: the same JSON as `TEXT`, and versions SQLite stores as 1.
    static let harmless = ["payload = CAST(payload AS TEXT)", "payload_version = '1'", "payload_version = 1.0"]

    static func store() throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        return (GRDBWorkoutEventStore(queue, now: { EventBuilders.start }), queue)
    }

    @Test("Every row either writer makes is the integer 1, and a row without a version is refused")
    func everyWrite_isVersion1_andNoWriterMayOmitIt() async throws {
        let (store, queue) = try Self.store()
        let log = [
            Contract.start(Self.workouts[0]), Contract.skip(.max, in: Self.workouts[1], at: .infinity),
            Contract.logged(set: 0, doneAt: 3, seq: 3, stamp: .nan), Contract.skip(1 << 63, EventBuilders.phone)
        ]
        _ = try await store.append(log)
        let settings = GRDBSettingsRepository(queue, now: { EventBuilders.start })
        try await settings.save(.default) // insert
        try await settings.save(SettingsRepositoryTests.custom) // upsert
        let versions = try await queue.read { database in
            try String.fetchAll(database, sql: """
            SELECT DISTINCT typeof(payload_version) || ':' || payload_version FROM workout_event
            UNION ALL SELECT DISTINCT typeof(payload_version) || ':' || payload_version FROM settings
            """)
        }
        #expect(versions == ["integer:1", "integer:1"])
        for table in ["workout_event", "settings"] {
            let column = try await queue.read { database in
                try Row.fetchOne(
                    database,
                    sql: "SELECT \"notnull\", dflt_value FROM pragma_table_info(?) WHERE name = ?",
                    arguments: [table, "payload_version"]
                )
                .map { "\($0[0] as Int),\(($0[1] as String?) ?? "no default")" }
            }
            #expect(column == "1,no default", "\(table)")
        }
        for insert in [
            "INSERT INTO workout_event (workout_id, device_id, seq, payload, created_at) VALUES ('w', 'd', 9, x'', '')",
            "INSERT INTO settings (id, payload, updated_at) VALUES ('other', '{}', '')"
        ] {
            await #expect(throws: DatabaseError.self) { try await queue.write { try $0.execute(sql: insert) } }
        }
    }

    @Test(
        "Random damage: each log reads its readable rows in order and counts the rest; a resend repairs exactly those",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func damagedRows_areLeftOutCountedAndKept(_ seed: PropertySeed) async throws {
        var random = seed.generator
        let (store, queue) = try Self.store()
        let log = Self.randomLog(using: &random)
        #expect(try await store.append(log) == log, "\(seed)")
        var damaged: Set<Int> = [] // indices into `log`; row id = index + 1
        for index in log.indices where Int.random(in: 0 ..< 3, using: &random) == 0 {
            let change = (Self.damages + Self.harmless).randomElement(using: &random) ?? ""
            try await queue.write { database in
                try database.execute(sql: "UPDATE workout_event SET \(change) WHERE id = ?", arguments: [index + 1])
            }
            if Self.damages.contains(change) {
                damaged.insert(index)
            }
        }
        let before = try await Self.dump(queue)
        for workout in Self.workouts {
            let mine = log.indices.filter { log[$0].workoutID == workout }
            let readable = mine.filter { !damaged.contains($0) }.map { log[$0] }
            #expect(try await store.envelopes(for: workout) == readable, "\(seed)")
            #expect(try await store.unreadableCount(for: workout) == mine.count { damaged.contains($0) }, "\(seed)")
            for device in Self.devices {
                let highest = mine.map { log[$0] }.filter { $0.device == device }.map(\.seq).max()
                #expect(try await store.highestSeq(for: workout, device: device) == highest, "\(seed)")
            }
        }
        #expect(try await Set(store.uncompactedWorkoutIDs()) == Set(log.map(\.workoutID)), "\(seed)")
        #expect(try await Self.dump(queue) == before, "\(seed)")
        // Fix round 2: a resend repairs exactly the damaged rows, in the order given, and leaves every other
        // row as it was.
        let resend = log.shuffled(using: &random)
        let lost = Set(damaged.map { log[$0] })
        let repaired = resend.filter(lost.contains)
        #expect(try await store.append(resend) == repaired, "\(seed)")
        let after = try await Self.dump(queue)
        #expect(before.indices.allSatisfy { damaged.contains($0) || before[$0] == after[$0] }, "\(seed)")
        for workout in Self.workouts {
            #expect(try await store.unreadableCount(for: workout) == 0, "\(seed)")
            #expect(try await store.envelopes(for: workout) == log.filter { $0.workoutID == workout }, "\(seed)")
        }
    }

    @Test(
        "A key whose row is unreadable is repaired by the first readable envelope with it; then contents count",
        arguments: ["payload_version = 2", "payload = x'FFFE00'"]
    )
    func append_overAnUnreadableKey_repairsIt(_ damage: String) async throws {
        let (store, queue) = try Self.store()
        _ = try await store.append([Contract.skip(1), Contract.skip(2)])
        try await queue.write { try $0.execute(sql: "UPDATE workout_event SET \(damage) WHERE seq = 1") }
        let unreadable = try await Self.dump(queue).first
        // Two different envelopes with that key in one batch: the first repairs, the second conflicts, and the
        // batch rolls back with the repair.
        await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(1).key)) {
            try await store.append([Contract.extend(1), Contract.skip(1)])
        }
        #expect(try await Self.dump(queue).first == unreadable)
        // (documents) The store cannot read what it replaces, so the first readable envelope wins, whichever it is.
        #expect(try await store.append([Contract.extend(1), Contract.skip(3)]) == [
            Contract.extend(1),
            Contract.skip(3)
        ])
        #expect(try await store.unreadableCount(for: Contract.workout) == 0)
        // Once readable, the key judges contents again, and a rival of a readable key rejects its whole batch.
        await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(1).key)) {
            try await store.append([Contract.skip(4), Contract.skip(1)])
        }
        await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(2).key)) {
            try await store.append([Contract.skip(5), Contract.extend(2)])
        }
        #expect(try await store.envelopes(for: Contract.workout) == [
            Contract.extend(1),
            Contract.skip(2),
            Contract.skip(3)
        ])
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 3)
    }

    @Test("Compacting a log deletes its unreadable rows with it and frees their keys; other logs keep theirs")
    func compact_deletesItsUnreadableRows_only() async throws {
        let (store, queue) = try Self.store()
        let (one, two) = (Self.workouts[0], Self.workouts[1])
        let first = [1, 2, 3].map { Contract.skip($0, in: one) }
        _ = try await store.append(first + [1, 2].map { Contract.skip($0, in: two) })
        try await queue.write { try $0.execute(sql: "UPDATE workout_event SET payload_version = 2") }
        #expect(try await store.envelopes(for: one).isEmpty)
        #expect(try await store.unreadableCount(for: one) == 3)
        #expect(try await Set(store.uncompactedWorkoutIDs()) == [one, two])
        try await store.compact(workout: one)
        #expect(try await Self.dump(queue).count == 2)
        #expect(try await store.unreadableCount(for: one) == 0)
        #expect(try await store.highestSeq(for: one, device: EventBuilders.watch) == nil)
        #expect(try await store.uncompactedWorkoutIDs() == [two])
        #expect(try await store.unreadableCount(for: two) == 2)
        #expect(try await store.append(first) == first)
        #expect(try await store.envelopes(for: one) == first)
    }
}

extension PayloadVersionAdversarialTests {
    /// Every `workout_event` row, every column quoted, so any change of value or storage class shows.
    static func dump(_ queue: DatabaseQueue) async throws -> [String] {
        try await queue.read { database in
            try String.fetchAll(database, sql: """
            SELECT id || ',' || quote(workout_id) || ',' || quote(device_id) || ',' || seq || ',' || quote(wall_clock)
                || ',' || quote(payload_version) || ',' || quote(payload) || ',' || quote(created_at)
            FROM workout_event ORDER BY id
            """)
        }
    }

    /// Up to five skips per device in each workout, keys unique per workout, shuffled across workouts.
    static func randomLog(using random: inout SeededGenerator) -> [EventEnvelope] {
        var log: [EventEnvelope] = []
        for workout in workouts {
            for device in devices {
                let count = Int.random(in: 0 ... 5, using: &random)
                log += (0 ..< count).map { Contract.skip(UInt64($0 + 1), device, in: workout) }
            }
        }
        return log.shuffled(using: &random)
    }
}
