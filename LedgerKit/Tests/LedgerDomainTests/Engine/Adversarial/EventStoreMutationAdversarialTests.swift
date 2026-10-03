import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: would a buggy store pass the contract? Each `Mutation` is one plausible F05 mistake.
/// Fix round 2 (finding 10) folded the tester's probes into `WorkoutEventStoreContract`, the suite F05
/// runs, so this is now that suite's own guard: its clauses must catch every mutant and pass
/// `InMemoryWorkoutEventStore`.
@Suite("WorkoutEventStore · contract mutants (adversarial, round 2)", .tags(.domain))
struct EventStoreMutationAdversarialTests {
    @Test("The in-memory reference store passes every contract clause")
    func inMemoryStore_passesEveryProbe() async {
        let found = await WorkoutEventStoreContract.violations { InMemoryWorkoutEventStore() }
        #expect(found.isEmpty, "\(found)")
    }

    @Test("Every mutant store fails at least one contract clause", arguments: MutantEventStore.Mutation.allCases)
    func mutant_isCaught(_ mutation: MutantEventStore.Mutation) async {
        let found = await WorkoutEventStoreContract.violations { MutantEventStore(mutation) }
        #expect(!found.isEmpty, "\(mutation) passed every contract clause")
    }
}

/// `InMemoryWorkoutEventStore`'s logic with one deliberate bug.
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
        /// Lists only logs that hold a `started` (round 2: replaces `liveIgnoresStarted`, whose list is
        /// gone). An envelope that arrived before its `started` would never be noticed.
        case listsOnlyStartedLogs
        /// Lists only logs with no `finished` or `discarded`, the old live list (round 2: replaces
        /// `finishedOnlyIsTerminal`). A kill before materialisation would lose the workout.
        case unlistsEndedLogs
        /// Deletes every workout's log.
        case compactsEverything
        /// Skips an envelope the engine would ignore (round 2): the store judges keys, not contents.
        case dropsMalformed
        /// Final fix round (finding 22): stores one more copy on each re-append (no unique index), while
        /// `append` still returns only what is new.
        case keepsCopies
        /// Final fix round (finding 22): keeps `wallClock` to the millisecond, as a `REAL` or `TEXT` column
        /// written in milliseconds would.
        case stampToMilliseconds
        /// Final fix round (finding 22): keeps payload dates to the millisecond, as GRDB's default JSON
        /// column encoding (`.millisecondsSince1970`) would.
        case payloadToMilliseconds
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
        for envelope in envelopes where mutation != .dropsMalformed || envelope.isWellFormed {
            let row = try row(envelope)
            guard let existing = stored(envelope, in: updated) else {
                updated[envelope.workoutID, default: []].append(row)
                fresh.append(envelope)
                continue
            }
            if existing == row || (mutation == .conflictComparesEventOnly && existing.event == envelope.event) {
                if mutation == .keepsCopies {
                    updated[envelope.workoutID, default: []].append(row)
                }
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

    /// It keeps envelopes as values, so it can read all of them.
    func unreadableCount(for _: WorkoutID) -> Int {
        0
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) -> UInt64? {
        let seqs = logs[workout, default: []].filter { $0.device == device }.map(\.seq)
        return mutation == .highestSeqIsLatest ? seqs.last : seqs.max()
    }

    func uncompactedWorkoutIDs() -> [WorkoutID] {
        logs.filter { _, log in
            switch mutation {
            case .listsOnlyStartedLogs:
                log.contains(where: Self.isStarted)
            case .unlistsEndedLogs:
                !log.contains(where: Self.isTerminal)
            default:
                true
            }
        }.map(\.key)
    }

    func compact(workout: WorkoutID) {
        if mutation == .compactsEverything {
            logs = [:]
        } else {
            logs[workout] = nil
        }
    }

    /// The envelope as this store keeps it.
    private func row(_ envelope: EventEnvelope) throws -> EventEnvelope {
        switch mutation {
        case .stampToMilliseconds:
            let milliseconds = (envelope.wallClock.timeIntervalSince1970 * 1000).rounded()
            return EventEnvelope(
                event: envelope.event, workoutID: envelope.workoutID, device: envelope.device, seq: envelope.seq,
                wallClock: Date(timeIntervalSince1970: milliseconds / 1000)
            )
        case .payloadToMilliseconds:
            let (encoder, decoder) = (JSONEncoder(), JSONDecoder())
            encoder.dateEncodingStrategy = .millisecondsSince1970
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try EventEnvelope(
                event: decoder.decode(WorkoutEvent.self, from: encoder.encode(envelope.event)),
                workoutID: envelope.workoutID, device: envelope.device, seq: envelope.seq, wallClock: envelope.wallClock
            )
        default:
            return envelope
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

    private static func isTerminal(_ envelope: EventEnvelope) -> Bool {
        switch envelope.event {
        case .finished, .discarded:
            true
        default:
            false
        }
    }
}
