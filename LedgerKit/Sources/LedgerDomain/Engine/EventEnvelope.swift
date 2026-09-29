import Foundation

/// A `WorkoutEvent` as one device recorded it: the unit that is logged, sent and replayed (ADR-004).
///
/// **Precondition:** `key` (device, seq) names exactly one envelope within a workout, so two envelopes
/// with the same key are copies of each other. Under it `<` is a strict total order on a workout's
/// envelopes and `replay` is a function of the envelope set; nothing breaks a tie between two different
/// envelopes that share a key. It is kept by:
/// - the creating device, which takes its next `seq` from `WorkoutEventStore.highestSeq` and runs
///   `.persist` before `.transmit`, so a seq it has sent is always in its store;
/// - `WorkoutEventStore.append`, which throws `EngineError.conflictingEnvelope` for a second, different
///   envelope with a stored key;
/// - the receiving host (F17), which checks keys the same way before it reduces.
public struct EventEnvelope: Hashable, Codable, Sendable, Comparable {
    public let event: WorkoutEvent
    public let workoutID: WorkoutID
    /// The device that created the envelope.
    public let device: DeviceID
    /// Strictly increasing per device within a workout, starting at 1.
    public let seq: UInt64
    /// The creating device's clock when the event happened: the first ordering key, and the time
    /// of events that carry none (rule 9).
    ///
    /// **Precondition (ADR-004 amendment, hybrid logical clock):** the host (F10/F17), not the reducer,
    /// stamps it as `max(now, newest wallClock seen or sent + 1 ms)`. An envelope then sorts after
    /// every envelope its device had sent or received, which keeps each device's `seq` order and causal
    /// order under clock skew. Raw clocks still converge, but on stamp order, not on what happened.
    public let wallClock: Date

    public init(event: WorkoutEvent, workoutID: WorkoutID, device: DeviceID, seq: UInt64, wallClock: Date) {
        self.event = event
        self.workoutID = workoutID
        self.device = device
        self.seq = seq
        self.wallClock = wallClock
    }

    /// The dedupe key (rule 12).
    public var key: EnvelopeKey {
        EnvelopeKey(device: device, seq: seq)
    }

    /// Rule 12: ordered by `wallClock`, then device ID, then `seq`, so every device that holds the
    /// same envelopes folds them in the same order. `UUID`'s order is its byte order, which is the
    /// order of its `uuidString`.
    public static func < (lhs: EventEnvelope, rhs: EventEnvelope) -> Bool {
        (lhs.wallClock, lhs.device.rawValue, lhs.seq) < (rhs.wallClock, rhs.device.rawValue, rhs.seq)
    }
}

/// Identifies an envelope within a workout's log: the creating device and its sequence number.
public struct EnvelopeKey: Hashable, Codable, Sendable {
    public let device: DeviceID
    public let seq: UInt64

    public init(device: DeviceID, seq: UInt64) {
        self.device = device
        self.seq = seq
    }
}
