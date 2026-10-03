#if DEBUG
    import Foundation
    import LedgerDomain

    /// `WorkoutEventStore`'s documented contract, in memory: the store the engine suites use to model a host,
    /// the reference F05's GRDB store must behave like (`WorkoutEventStoreContract` in LedgerTestSupport runs
    /// against both), and the previews' event log. F04 wrote it in `LedgerDomainTests`; F07 moved it here.
    public actor InMemoryWorkoutEventStore: WorkoutEventStore {
        private var logs: [WorkoutID: [EnvelopeKey: EventEnvelope]] = [:]

        /// An empty store, or one holding `envelopes` (as one `append`; a conflicting one is left out).
        public init(_ envelopes: [EventEnvelope] = []) {
            for envelope in envelopes where logs[envelope.workoutID]?[envelope.key] == nil {
                logs[envelope.workoutID, default: [:]][envelope.key] = envelope
            }
        }

        /// Stores the envelopes whose key is new, all or none: a conflicting key rejects the whole batch.
        public func append(_ envelopes: [EventEnvelope]) throws -> [EventEnvelope] {
            var updated = logs
            var fresh: [EventEnvelope] = []
            for envelope in envelopes {
                switch updated[envelope.workoutID]?[envelope.key] {
                case nil:
                    updated[envelope.workoutID, default: [:]][envelope.key] = envelope
                    fresh.append(envelope)
                case envelope:
                    continue
                default:
                    throw EngineError.conflictingEnvelope(envelope.key)
                }
            }
            logs = updated
            return fresh
        }

        public func envelopes(for workout: WorkoutID) -> [EventEnvelope] {
            Array(logs[workout, default: [:]].values)
        }

        /// It keeps envelopes as values, so it can read all of them.
        public func unreadableCount(for _: WorkoutID) -> Int {
            0
        }

        public func highestSeq(for workout: WorkoutID, device: DeviceID) -> UInt64? {
            logs[workout]?.keys.filter { $0.device == device }.map(\.seq).max()
        }

        public func uncompactedWorkoutIDs() -> [WorkoutID] {
            Array(logs.keys)
        }

        public func compact(workout: WorkoutID) {
            logs[workout] = nil
        }
    }
#endif
