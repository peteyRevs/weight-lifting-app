import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 3 (G2 after fix round 2): the power of `WorkoutEventStoreContract` (decision C) against stores
/// F05 could plausibly write, and `uncompactedWorkoutIDs` classified by replay (decision D) around a
/// discard.
@Suite("WorkoutEventStore · contract power and lifecycle (adversarial, round 3)", .tags(.domain))
struct Round3StoreAdversarialTests {
    typealias Adv = EngineAdv

    @Test(
        """
        Finding 22: the contract suite passes stores that lose sub-second date precision (GRDB's default JSON \
        column encoding, or the .iso8601 codec in F17's brief) or keep a copy per re-append; its fixtures \
        all sit on whole or half seconds
        """,
        arguments: LossyEventStore.Loss.allCases
    )
    func contract_catchesLossyStores(_ loss: LossyEventStore.Loss) async throws {
        let found = await WorkoutEventStoreContract.violations { LossyEventStore(loss) }
        #expect(!found.isEmpty, "\(loss) passed every contract clause")
        // What the loss does to a real, sub-millisecond HLC stamp. Final fix round: this store is lossy by
        // construction, so this now pins that the loss is real (the clause above has something to catch).
        let store = LossyEventStore(loss)
        let precise = Adv.env(Adv.logged(0, 0, doneAt: 10.493_826_8), Adv.watch, seq: 1, at: 10.493_826_8)
        _ = try await store.append([precise])
        _ = try await store.append([precise])
        #expect(await store.envelopes(for: Adv.workoutID) != [precise], "\(loss) reads back exactly")
    }

    /// Final fix round: the lossy store cannot be fixed, only rejected, so this now documents the
    /// consequence and asserts that the contract suite rejects such a store.
    @Test(
        """
        Finding 22, consequence (documents): a store that keeps whole seconds reorders a causal pair from two \
        devices within one second, so the phone's un-log of the watch's set is lost on replay (finding 6 \
        again); the contract suite rejects that store
        """
    )
    func iso8601Store_losesAnUnlog() async throws {
        let log = Adv.env(Adv.logged(0, 0, doneAt: 10.1), Adv.watch, seq: 1, at: 10.1)
        let unlog = Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), seq: 2, at: 10.4)
        let precise = WorkoutEngine.replay([Adv.start(), log, unlog])
        #expect(Adv.row(precise, 0, 0)?.isDone == false)
        let store = LossyEventStore(.iso8601JSON)
        _ = try await store.append([Adv.start(), log, unlog])
        let stored = await WorkoutEngine.replay(store.envelopes(for: Adv.workoutID))
        #expect(Adv.row(stored, 0, 0)?.isDone == true, "the un-log is lost after a reload")
        #expect(await !WorkoutEventStoreContract.violations { LossyEventStore(.iso8601JSON) }.isEmpty)
    }
}

// MARK: - Decision D around a discard (out of scope for F04, noted for F05 and F17)

extension Round3StoreAdversarialTests {
    @Test(
        """
        Out of scope (documents): the phone discards and runs .discardLog at once; the partitioned watch's \
        envelopes then land in an empty log that replays to nil, which the launch step keeps and asks to be \
        resent for ever: under ADR-004 rule 4 the watch resends only its own, never the phone's started
        """
    )
    func discardLogThenLatePeer_orphanIsKeptForever() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let phone = [Adv.start(), Adv.env(.discarded(endedAt: engineTime(50)), seq: 2, at: 50)]
        _ = try await store.append(phone)
        #expect(try await WorkoutEngine.replay(store.envelopes(for: Adv.workoutID))?.phase == .discarded)
        try await store.compact(workout: Adv.workoutID)
        let watch = [
            Adv.env(Adv.logged(0, 0, doneAt: 20), Adv.watch, seq: 1, at: 20),
            Adv.env(Adv.logged(0, 1, doneAt: 60), Adv.watch, seq: 2, at: 60)
        ]
        _ = try await store.append(watch)
        for _ in 0 ..< 3 {
            #expect(try await LaunchStep.run(store) == [Adv.workoutID: .keptForResend])
        }
        // The watch never learns of the discard from the phone's log: the phone has none left to resend.
        #expect(try await store.highestSeq(for: Adv.workoutID, device: Adv.phone) == nil)
    }
}

/// Stores that keep `WorkoutEventStore`'s key rules but lose information F05 could plausibly lose.
actor LossyEventStore: WorkoutEventStore {
    enum Loss: CaseIterable, Sendable {
        /// Envelopes stored as a GRDB JSON column: its default encoder writes dates as
        /// `.millisecondsSince1970`, whose ×1000 and ÷1000 do not round-trip every `Date`.
        case millisecondsJSON
        /// Envelopes stored with the `.iso8601` codec F17's brief sketches: whole seconds.
        case iso8601JSON
        /// Keeps one more row per re-append (no unique index), while `append` still returns only new ones.
        case keepsCopies
    }

    let loss: Loss
    private var logs: [WorkoutID: [EventEnvelope]] = [:]

    init(_ loss: Loss) {
        self.loss = loss
    }

    func append(_ envelopes: [EventEnvelope]) throws -> [EventEnvelope] {
        var updated = logs
        var fresh: [EventEnvelope] = []
        for envelope in envelopes {
            let row = try stored(envelope)
            let existing = updated[envelope.workoutID, default: []].first { $0.key == envelope.key }
            switch existing {
            case nil:
                fresh.append(envelope)
            case row:
                guard loss == .keepsCopies else {
                    continue
                }
            default:
                throw EngineError.conflictingEnvelope(envelope.key)
            }
            updated[envelope.workoutID, default: []].append(row)
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

    /// The envelope as it reads back from this store.
    private func stored(_ envelope: EventEnvelope) throws -> EventEnvelope {
        let (encoder, decoder) = (JSONEncoder(), JSONDecoder())
        switch loss {
        case .millisecondsJSON:
            (encoder.dateEncodingStrategy, decoder.dateDecodingStrategy) = (
                .millisecondsSince1970,
                .millisecondsSince1970
            )
        case .iso8601JSON:
            (encoder.dateEncodingStrategy, decoder.dateDecodingStrategy) = (.iso8601, .iso8601)
        case .keepsCopies:
            return envelope
        }
        return try decoder.decode(EventEnvelope.self, from: encoder.encode(envelope))
    }
}
