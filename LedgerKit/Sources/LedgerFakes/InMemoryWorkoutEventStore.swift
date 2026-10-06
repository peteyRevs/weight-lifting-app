#if DEBUG
    import Foundation
    import LedgerDomain
    import Synchronization

    /// `WorkoutEventStore`'s documented contract, in memory: the store the engine suites use to model a host,
    /// the reference F05's GRDB store must behave like (`WorkoutEventStoreContract` in LedgerTestSupport runs
    /// against both), and the previews' event log. F04 wrote it in `LedgerDomainTests`; F07 moved it here.
    public actor InMemoryWorkoutEventStore: WorkoutEventStore {
        /// Behind a `Mutex` although this is an actor: `InMemoryStores`' workout repository drops a finished
        /// workout's log inside its own write (`drop(_:)`), as the database does in the save's transaction, and
        /// a write under a lock cannot wait for an actor.
        private let logs: Mutex<[WorkoutID: [EnvelopeKey: EventEnvelope]]>

        /// An empty store, or one holding `envelopes` (as one `append`; a conflicting one is left out).
        public init(_ envelopes: [EventEnvelope] = []) {
            var initial: [WorkoutID: [EnvelopeKey: EventEnvelope]] = [:]
            for envelope in envelopes where initial[envelope.workoutID]?[envelope.key] == nil {
                initial[envelope.workoutID, default: [:]][envelope.key] = envelope
            }
            logs = Mutex(initial)
        }

        /// Stores the envelopes whose key is new, all or none: one `EnvelopeCodec` cannot encode (a NaN weight
        /// throws `EncodingError`), or a conflicting key, rejects the whole batch. Each is kept as the database
        /// keeps it, decoded from its encoding, and compared with what it was stored as.
        public func append(_ envelopes: [EventEnvelope]) throws -> [EventEnvelope] {
            let stored = try envelopes.map { envelope in
                try EnvelopeCodec.decode(EnvelopeCodec.encode(envelope), version: EnvelopeCodec.version)
            }
            return try logs.withLock { logs throws(EngineError) in
                var updated = logs
                var fresh: [EventEnvelope] = []
                for (envelope, kept) in zip(envelopes, stored) {
                    switch updated[envelope.workoutID]?[envelope.key] {
                    case nil:
                        updated[envelope.workoutID, default: [:]][envelope.key] = kept
                        fresh.append(envelope)
                    case envelope:
                        continue
                    default:
                        throw .conflictingEnvelope(envelope.key)
                    }
                }
                logs = updated
                return fresh
            }
        }

        public func envelopes(for workout: WorkoutID) -> [EventEnvelope] {
            logs.withLock { Array($0[workout, default: [:]].values) }
        }

        /// It keeps envelopes as values, so it can read all of them.
        public func unreadableCount(for _: WorkoutID) -> Int {
            0
        }

        public func highestSeq(for workout: WorkoutID, device: DeviceID) -> UInt64? {
            logs.withLock { $0[workout]?.keys.filter { $0.device == device }.map(\.seq).max() }
        }

        public func uncompactedWorkoutIDs() -> [WorkoutID] {
            logs.withLock { Array($0.keys) }
        }

        public func compact(workout: WorkoutID) {
            drop(workout)
        }

        /// `compact(workout:)` for the linked workout repository, which calls it under its own write's lock:
        /// the workout is stored and its log gone in one step, as in the database's one transaction.
        nonisolated func drop(_ workout: WorkoutID) {
            logs.withLock { $0[workout] = nil }
        }
    }
#endif
