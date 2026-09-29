import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 4 (G2 close-out after the re-plan): the store contract after decision 5 (finding 22).
@Suite("WorkoutEventStore · contract after the re-plan (adversarial, round 4)", .tags(.domain))
struct Round4StoreAdversarialTests {
    typealias Adv = EngineAdv

    static let exactClause = "an envelope reads back once and exactly"

    @Test(
        """
        The contract suite kills all 14 mutants and passes the reference store; the three new mutants \
        (copies, millisecond stamps, millisecond payloads) each fail the new exact read-back clause
        """
    )
    func contract_killsItsFourteenMutants() async {
        #expect(MutantEventStore.Mutation.allCases.count == 14)
        #expect(await WorkoutEventStoreContract.violations { InMemoryEventStore() }.isEmpty)
        for mutation in MutantEventStore.Mutation.allCases {
            let found = await WorkoutEventStoreContract.violations { MutantEventStore(mutation) }
            #expect(!found.isEmpty, "\(mutation) survives")
            if [.keepsCopies, .stampToMilliseconds, .payloadToMilliseconds].contains(mutation) {
                #expect(found.contains { $0.hasPrefix(Self.exactClause) }, "\(mutation): \(found)")
            }
        }
    }

    @Test(
        """
        Out of scope, for F05 (documents): the exact read-back clause has one stamp fixture, and it happens to \
        survive a trip through timeIntervalSince1970 (GRDB's .timeIntervalSince1970 date strategy); a store \
        keeping wallClock that way passes every clause, while about half of real sub-second stamps read back \
        one ulp off, and a store that compares a duplicate with what it reads back rejects the batch
        """
    )
    func since1970Stamps_passTheContract_butAlterHalfOfRealStamps() async throws {
        #expect(await WorkoutEventStoreContract.violations { Since1970StampStore() }.isEmpty)
        var altered = 0
        for step in 1 ... 1000 {
            let stamp = engineTime(Double(step) * 0.731)
            altered += Date(timeIntervalSince1970: stamp.timeIntervalSince1970) == stamp ? 0 : 1
        }
        #expect(altered > 300, "\(altered) of 1,000 stamps altered")
        // A realistic HLC stamp that does not survive, delivered twice (mirroring plus the fallback).
        let stamp = engineTime(10.493_826_8)
        #expect(Date(timeIntervalSince1970: stamp.timeIntervalSince1970) != stamp)
        let log = Adv.env(Adv.logged(0, 0, doneAt: 10.493_826_8), Adv.watch, seq: 1, at: 10.493_826_8)
        let next = Adv.env(Adv.logged(0, 1, doneAt: 20), Adv.watch, seq: 2, at: 20)
        let store = Since1970StampStore()
        _ = try await store.append([Adv.start(), log])
        await #expect(throws: EngineError.conflictingEnvelope(log.key)) {
            try await store.append([log, next])
        }
        let highest = try await store.highestSeq(for: Adv.workoutID, device: Adv.watch)
        #expect(highest == 1, "set 2 was not stored")
    }
}

/// `InMemoryEventStore`'s rules, with `wallClock` kept as seconds since 1970 in a `Double` (as a `REAL`
/// column written with GRDB's `.timeIntervalSince1970` strategy would), and a conflict check that compares
/// an incoming envelope with what it reads back.
actor Since1970StampStore: WorkoutEventStore {
    private var logs: [WorkoutID: [EventEnvelope]] = [:]

    static func row(_ envelope: EventEnvelope) -> EventEnvelope {
        EventEnvelope(
            event: envelope.event, workoutID: envelope.workoutID, device: envelope.device, seq: envelope.seq,
            wallClock: Date(timeIntervalSince1970: envelope.wallClock.timeIntervalSince1970)
        )
    }

    func append(_ envelopes: [EventEnvelope]) throws -> [EventEnvelope] {
        var updated = logs
        var fresh: [EventEnvelope] = []
        for envelope in envelopes {
            switch updated[envelope.workoutID, default: []].first(where: { $0.key == envelope.key }) {
            case nil:
                fresh.append(envelope)
                updated[envelope.workoutID, default: []].append(Self.row(envelope))
            case envelope:
                continue
            default:
                throw EngineError.conflictingEnvelope(envelope.key)
            }
        }
        logs = updated
        return fresh
    }

    func envelopes(for workout: WorkoutID) -> [EventEnvelope] {
        logs[workout, default: []]
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) -> UInt64? {
        logs[workout]?.filter { $0.device == device }.map(\.seq).max()
    }

    func uncompactedWorkoutIDs() -> [WorkoutID] {
        Array(logs.keys)
    }

    func compact(workout: WorkoutID) {
        logs[workout] = nil
    }
}
