import Foundation
@testable import LedgerDomain

/// `WorkoutEventStore`'s documented contract, in memory: the store the engine suites use to model a
/// host, and the reference F05's GRDB store must behave like (`WorkoutEventStoreContractTests`).
actor InMemoryEventStore: WorkoutEventStore {
    private var logs: [WorkoutID: [EnvelopeKey: EventEnvelope]] = [:]

    /// Stores the envelopes whose key is new, all or none: a conflicting key rejects the whole batch.
    func append(_ envelopes: [EventEnvelope]) throws -> [EventEnvelope] {
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

    func envelopes(for workout: WorkoutID) -> [EventEnvelope] {
        Array(logs[workout, default: [:]].values)
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) -> UInt64? {
        logs[workout]?.keys.filter { $0.device == device }.map(\.seq).max()
    }

    func liveWorkoutIDs() -> [WorkoutID] {
        workoutIDs { log in log.contains(where: Self.isStarted) && !log.contains(where: Self.isTerminal) }
    }

    func unmaterializedWorkoutIDs() -> [WorkoutID] {
        workoutIDs { log in log.contains(where: Self.isTerminal) }
    }

    func compact(workout: WorkoutID) {
        logs[workout] = nil
    }

    private func workoutIDs(where matches: ([EventEnvelope]) -> Bool) -> [WorkoutID] {
        logs.filter { matches(Array($0.value.values)) }.map(\.key)
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
