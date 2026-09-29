import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: would a buggy store pass the contract? Each `Mutation` is one plausible F05 mistake. The
/// probes in `StoreProbe` must catch every one and pass `InMemoryEventStore`. (Which of these mutants
/// also pass the implementer's `WorkoutEventStoreContractTests` is recorded in test-findings.md, finding 10.)
@Suite("WorkoutEventStore · contract mutants (adversarial, round 2)", .tags(.domain))
struct EventStoreMutationAdversarialTests {
    @Test("The in-memory reference store passes every probe")
    func inMemoryStore_passesEveryProbe() async {
        let found = await StoreProbe.violations { InMemoryEventStore() }
        #expect(found.isEmpty, "\(found)")
    }

    @Test("Every mutant store fails at least one probe", arguments: MutantEventStore.Mutation.allCases)
    func mutant_isCaught(_ mutation: MutantEventStore.Mutation) async {
        let found = await StoreProbe.violations { MutantEventStore(mutation) }
        #expect(!found.isEmpty, "\(mutation) passed every probe")
    }
}

/// `InMemoryEventStore`'s logic with one deliberate bug.
actor MutantEventStore: WorkoutEventStore {
    enum Mutation: String, CaseIterable, Sendable {
        /// Returns the whole batch, not only what it newly stored.
        case returnsAllGiven
        /// Returns the new envelopes sorted by `seq`, not in the order given.
        case sortsNewBySeq
        /// Keeps the first of two different envelopes that share a key within one batch.
        case keepsFirstOfBatchConflict
        /// Treats a same-key envelope with the same event as a duplicate, whatever its stamp.
        case conflictComparesEventOnly
        /// Keeps the envelopes before the conflicting one.
        case storesPartialBatch
        /// Keys envelopes by (device, seq) across workouts.
        case keysAcrossWorkouts
        /// Reports the device's latest stored `seq`, not its highest.
        case highestSeqIsLatest
        /// Lists every log with no terminal as live, started or not.
        case liveIgnoresStarted
        /// Treats only `finished` as terminal.
        case finishedOnlyIsTerminal
        /// Deletes every workout's log.
        case compactsEverything
    }

    let mutation: Mutation
    /// Each workout's envelopes in the order they were stored.
    private var logs: [WorkoutID: [EventEnvelope]] = [:]

    init(_ mutation: Mutation) {
        self.mutation = mutation
    }

    func append(_ envelopes: [EventEnvelope]) throws -> [EventEnvelope] {
        var updated = logs
        var fresh: [EventEnvelope] = []
        for envelope in envelopes {
            guard let existing = stored(envelope, in: updated) else {
                updated[envelope.workoutID, default: []].append(envelope)
                fresh.append(envelope)
                continue
            }
            if existing == envelope || (mutation == .conflictComparesEventOnly && existing.event == envelope.event) {
                continue
            }
            if mutation == .keepsFirstOfBatchConflict, fresh.contains(existing) {
                continue
            }
            if mutation == .storesPartialBatch {
                logs = updated
            }
            throw EngineError.conflictingEnvelope(envelope.key)
        }
        logs = updated
        switch mutation {
        case .returnsAllGiven:
            return envelopes
        case .sortsNewBySeq:
            return fresh.sorted { $0.seq < $1.seq }
        default:
            return fresh
        }
    }

    func envelopes(for workout: WorkoutID) -> [EventEnvelope] {
        logs[workout, default: []]
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) -> UInt64? {
        let seqs = logs[workout, default: []].filter { $0.device == device }.map(\.seq)
        return mutation == .highestSeqIsLatest ? seqs.last : seqs.max()
    }

    func liveWorkoutIDs() -> [WorkoutID] {
        logs.filter { _, log in
            (mutation == .liveIgnoresStarted || log.contains(where: Self.isStarted)) && !log.contains(where: isTerminal)
        }.map(\.key)
    }

    func unmaterializedWorkoutIDs() -> [WorkoutID] {
        logs.filter { _, log in log.contains(where: isTerminal) }.map(\.key)
    }

    func compact(workout: WorkoutID) {
        if mutation == .compactsEverything {
            logs = [:]
        } else {
            logs[workout] = nil
        }
    }

    private func stored(_ envelope: EventEnvelope, in logs: [WorkoutID: [EventEnvelope]]) -> EventEnvelope? {
        let pool = mutation == .keysAcrossWorkouts ? logs.values.flatMap(\.self) : logs[envelope.workoutID, default: []]
        return pool.first { $0.key == envelope.key }
    }

    private static func isStarted(_ envelope: EventEnvelope) -> Bool {
        if case .started = envelope.event {
            return true
        }
        return false
    }

    private func isTerminal(_ envelope: EventEnvelope) -> Bool {
        switch envelope.event {
        case .finished:
            true
        case .discarded:
            mutation != .finishedOnlyIsTerminal
        default:
            false
        }
    }
}
