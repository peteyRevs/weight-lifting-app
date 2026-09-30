import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 3 (close-out): fix round 2's `newestWallClock()` (review SF3) read from the
/// `wall_clock` column: unreadable rows count, `NULL` and non-finite stamps never do, a compacted log is
/// forgotten, and the result is the largest over every uncompacted workout. A seeded model then checks the
/// repair (SF2), every read, and the clock together against the documented rules.
@Suite("Adversarial S1 round 3 · clock recovery", .tags(.persistence), .timeLimit(.minutes(1)))
struct ClockRecoveryAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    static let third = WorkoutID(EventBuilders.uuid(0xF1B3))

    static func store() throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        return (GRDBWorkoutEventStore(queue, now: { EventBuilders.start }), queue)
    }

    @Test("An unreadable row in another workout holds the newest stamp; compacting logs forgets theirs")
    func newest_countsUnreadable_acrossWorkouts_andForgetsCompacted() async throws {
        let (store, queue) = try Self.store()
        _ = try await store.append([
            Contract.skip(1, at: 5), Contract.skip(2, at: 7.000_000_4), Contract.skip(1, in: Contract.other, at: 9),
            Contract.skip(1, in: Self.third, at: 20)
        ])
        try await store.compact(workout: Self.third)
        try await RowRepairAdversarialTests.damage(
            Contract.skip(1, in: Contract.other, at: 9), with: "payload_version = 2", in: queue
        )
        #expect(try await store.unreadableCount(for: Contract.other) == 1)
        #expect(try await store.newestWallClock() == Contract.at(9))
        try await store.compact(workout: Contract.other)
        #expect(try await store.newestWallClock() == Contract.at(7.000_000_4))
        try await store.compact(workout: Contract.workout)
        #expect(try await store.newestWallClock() == nil)
    }

    @Test("NULL and ±∞ in wall_clock never count, even from another writer; finite extremes do, exactly")
    func newest_skipsNullAndInfinities_keepsFiniteExtremes() async throws {
        let (store, queue) = try Self.store()
        _ = try await store.append([Contract.skip(1, at: .nan), Contract.skip(2, at: .infinity)])
        #expect(try await store.newestWallClock() == nil)
        /// Another writer's rows (unreadable, version 2), with `clock` as the SQL for their wall_clock.
        func foreign(_ seq: Int64, _ clock: String) async throws {
            try await queue.write { database in
                try database.execute(
                    sql: """
                    INSERT INTO workout_event
                        (workout_id, device_id, seq, wall_clock, payload_version, payload, created_at)
                    VALUES (?, ?, ?, \(clock), 2, x'00', 'foreign')
                    """,
                    arguments: [ColumnCodec.text(Contract.workout), ColumnCodec.text(EventBuilders.phone), seq]
                )
            }
        }
        try await foreign(1, "9e999")
        try await foreign(2, "-9e999")
        try await foreign(3, "NULL")
        #expect(try await store.newestWallClock() == nil)
        try await foreign(4, "-1e300")
        #expect(try await store.newestWallClock() == Date(timeIntervalSinceReferenceDate: -1e300))
        try await foreign(5, "\(Double.greatestFiniteMagnitude)")
        #expect(try await store.newestWallClock() == Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude))
        #expect(try await store.unreadableCount(for: Contract.workout) == 5)
    }

    @Test(
        "Seeded model: repairs, conflicts, compaction, every read and the clock follow the documented rules",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func model_repairAndClock(_ seed: PropertySeed) async throws {
        var random = seed.generator
        let (store, queue) = try Self.store()
        var model = RepairModel()
        let log = RepairModel.keys.filter { _ in Bool.random(using: &random) }
            .map { RepairModel.envelope($0, stamp: RepairModel.stamp(using: &random)) }
        #expect(try await store.append(log).count == log.count, "\(seed)")
        _ = model.append(log)
        for index in model.rows.indices where Int.random(in: 0 ..< 3, using: &random) == 0 {
            let damage = RowRepairAdversarialTests.damages.randomElement(using: &random) ?? ""
            try await RowRepairAdversarialTests.damage(model.rows[index].envelope, with: damage, in: queue)
            model.rows[index].readable = false
        }
        try await model.check(store, "\(seed) damaged")
        for step in 0 ..< 6 {
            if Int.random(in: 0 ..< 5, using: &random) == 0 {
                let workout = RepairModel.workouts.randomElement(using: &random) ?? Contract.workout
                try await store.compact(workout: workout)
                model.rows.removeAll { $0.envelope.workoutID == workout }
            } else {
                let batch = model.batch(using: &random)
                let expected = model.append(batch)
                let actual: Result<[EventEnvelope], EngineError>
                do {
                    actual = try await .success(store.append(batch))
                } catch let error as EngineError {
                    actual = .failure(error)
                }
                #expect(RepairModel.matches(actual, expected), "\(seed) step \(step): \(actual) vs \(expected)")
            }
            try await model.check(store, "\(seed) step \(step)")
        }
    }
}
