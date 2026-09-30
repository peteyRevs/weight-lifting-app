import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 1: `append`'s batch semantics beyond the contract's fixtures, `highestSeq` across
/// the signed/unsigned boundary, compaction across many workouts, and appends racing from many tasks.
@Suite("Adversarial S1 · event store batches", .tags(.persistence), .timeLimit(.minutes(1)))
struct EventStoreBatchAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    static func store() throws -> (GRDBWorkoutEventStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        return (GRDBWorkoutEventStore(queue, now: { EventBuilders.start }), queue)
    }

    static func outcome(_ body: () async throws -> [EventEnvelope]) async -> Result<[EventEnvelope], any Error> {
        do {
            return try await .success(body())
        } catch {
            return .failure(error)
        }
    }

    static func appendEach(_ batches: [[EventEnvelope]], to store: GRDBWorkoutEventStore) async throws {
        for batch in batches {
            _ = try await store.append(batch)
        }
    }

    static func rows(_ queue: DatabaseQueue) async throws -> Int {
        try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workout_event") ?? -1 }
    }

    @Test("A conflict mid-batch leaves no trace: no row, no newly listed workout, highestSeq unchanged")
    func conflictMidBatch_leavesNoTrace() async throws {
        let (store, queue) = try Self.store()
        let elsewhere = WorkoutID(EventBuilders.uuid(0xF1C1))
        _ = try await store.append([Contract.skip(1), Contract.skip(5, EventBuilders.phone)])
        let batch = [
            Contract.skip(1, in: elsewhere), Contract.skip(9), Contract.skip(9, EventBuilders.phone),
            Contract.extend(1), Contract.skip(10), Contract.skip(2, in: elsewhere)
        ]
        await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(1).key)) {
            try await store.append(batch)
        }
        #expect(try await Self.rows(queue) == 2)
        #expect(try await store.uncompactedWorkoutIDs() == [Contract.workout])
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 1)
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.phone) == 5)
        #expect(try await store.highestSeq(for: elsewhere, device: EventBuilders.watch) == nil)
    }

    @Test("With two rivals in one batch, the error names the first in the order given")
    func twoRivals_errorNamesTheFirstGiven() async throws {
        let (store, queue) = try Self.store()
        _ = try await store.append([Contract.skip(1), Contract.skip(2)])
        await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(2).key)) {
            try await store.append([Contract.skip(3), Contract.extend(2), Contract.extend(1)])
        }
        #expect(try await Self.rows(queue) == 2)
    }

    @Test("Duplicates within a batch are stored once and returned once, where they first appear")
    func duplicatesWithinBatch_storedAndReturnedOnce() async throws {
        let (store, queue) = try Self.store()
        let (one, two, three) = (Contract.skip(1), Contract.skip(2), Contract.skip(3))
        #expect(try await store.append([two, one, two, three, one, two]) == [two, one, three])
        #expect(try await Self.rows(queue) == 3)
        #expect(try await store.append([]).isEmpty)
        #expect(try await Self.rows(queue) == 3)
    }

    @Test("A copy then a rival within one batch is a conflict, and neither is stored")
    func copyThenRivalWithinBatch_storesNothing() async throws {
        let (store, queue) = try Self.store()
        await #expect(throws: EngineError.conflictingEnvelope(Contract.skip(4).key)) {
            try await store.append([Contract.skip(4), Contract.skip(4), Contract.extend(4)])
        }
        #expect(try await Self.rows(queue) == 0)
        #expect(try await store.uncompactedWorkoutIDs().isEmpty)
    }

    @Test(
        "highestSeq is the unsigned maximum of any seq set across 2^63, and only for its own device",
        arguments: [
            [0], [UInt64(Int64.max)], [UInt64(Int64.max), 1 << 63], [1 << 63, (1 << 63) + 1],
            [.max - 1, .max], [.max, 0], [5, UInt64(Int64.max), 3], [(1 << 63) - 1, 1 << 63, 1, .max - 7]
        ] as [[UInt64]]
    )
    func highestSeq_isUnsignedMaximum(_ seqs: [UInt64]) async throws {
        let (store, _) = try Self.store()
        _ = try await store.append(seqs.map { Contract.skip($0, at: 1) } + [Contract.skip(.max, EventBuilders.phone)])
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == seqs.max())
        #expect(try await store.highestSeq(for: Contract.other, device: EventBuilders.watch) == nil)
    }

    @Test("Across ten workouts, compact unlists exactly its own; unknown and repeated compacts are no-ops")
    func compactAcrossWorkouts_unlistsOnlyItsOwn() async throws {
        let (store, queue) = try Self.store()
        let workouts = (0 ..< 10).map { WorkoutID(EventBuilders.uuid(0xF200 + $0)) }
        _ = try await store.append(workouts.flatMap { [Contract.skip(1, in: $0), Contract.skip(2, in: $0)] })
        for workout in workouts.enumerated() where workout.offset.isMultiple(of: 2) {
            try await store.compact(workout: workout.element)
        }
        try await store.compact(workout: WorkoutID(EventBuilders.uuid(0xDEAD)))
        try await store.compact(workout: workouts[0])
        let odd = Set(workouts.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element))
        #expect(try await Set(store.uncompactedWorkoutIDs()) == odd)
        #expect(try await store.uncompactedWorkoutIDs().count == 5, "each workout listed once")
        #expect(try await Self.rows(queue) == 10)
        // A resend after compaction is new again: stored, listed, and its seq counted.
        #expect(try await store.append([Contract.skip(2, in: workouts[0])]) == [Contract.skip(2, in: workouts[0])])
        #expect(try await store.highestSeq(for: workouts[0], device: EventBuilders.watch) == 2)
        #expect(try await Set(store.uncompactedWorkoutIDs()) == odd.union([workouts[0]]))
    }

    @Test("Sixteen racing appends lose nothing, return each envelope once, and keep every batch atomic")
    func racingAppends_loseNothing_andStayAtomic() async throws {
        let (store, queue) = try Self.store()
        let shared = (1 ... 3).map { Contract.skip($0) }
        let versions = [100.0, 100.5].map { Contract.skip(100, EventBuilders.phone, at: $0) } // one key, two stamps
        var random = SeededGenerator(seed: 0xF05)
        let batches = (0 ..< 16).map { task in
            (shared + [Contract.skip(1000 + UInt64(task), EventBuilders.phone), versions[task % 2]])
                .shuffled(using: &random)
        }
        let outcomes = await withTaskGroup(of: (Int, Result<[EventEnvelope], any Error>).self) { group in
            for (task, batch) in batches.enumerated() {
                group.addTask { await (task, Self.outcome { try await store.append(batch) }) }
            }
            return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }
        let stored = try await Set(store.envelopes(for: Contract.workout))
        let winner = try #require(versions.first(where: stored.contains))
        #expect(!stored.isSuperset(of: versions), "both versions of one key were stored")
        var returned: [EventEnvelope] = []
        for (task, batch) in batches.enumerated() {
            let unique = Contract.skip(1000 + UInt64(task), EventBuilders.phone)
            switch outcomes[task] {
            case let .success(fresh)?:
                #expect(batch.contains(winner) && stored.contains(unique), "task \(task)")
                returned += fresh
            case let .failure(error)?:
                #expect(error as? EngineError == .conflictingEnvelope(winner.key), "task \(task): \(error)")
                #expect(!batch.contains(winner) && !stored.contains(unique), "task \(task) stored part of a batch")
            case nil:
                Issue.record("task \(task) did not finish")
            }
        }
        #expect(returned.count == Set(returned).count, "an envelope was returned to two tasks")
        #expect(Set(returned) == stored)
        #expect(try await Self.rows(queue) == stored.count)
    }

    @Test("A reader racing a writer never sees part of a batch")
    func readerRacingWriter_seesWholeBatchesOnly() async throws {
        let (store, _) = try Self.store()
        let batches = (0 ..< 20).map { batch in (1 ... 10).map { Contract.skip(UInt64(batch * 10 + $0)) } }
        async let written: Void = Self.appendEach(batches, to: store)
        var counts: [Int] = []
        for _ in 0 ..< 60 {
            try await counts.append(store.envelopes(for: Contract.workout).count)
        }
        try await written
        #expect(counts.allSatisfy { $0.isMultiple(of: 10) }, "\(counts)")
        #expect(try await store.envelopes(for: Contract.workout).count == 200)
    }
}
