import Foundation

/// A `WorkoutEvent` as one device recorded it: the unit that is logged, sent and replayed (ADR-004).
///
/// `key` (device, seq) names exactly one envelope: a device never reuses a `seq` within a workout, so
/// two envelopes with the same key are copies of each other (`EngineError.conflictingEnvelope`
/// otherwise). Under that invariant `<` is a strict total order on a workout's envelopes.
public struct EventEnvelope: Hashable, Codable, Sendable, Comparable {
    public let event: WorkoutEvent
    public let workoutID: WorkoutID
    /// The device that created the envelope.
    public let device: DeviceID
    /// Strictly increasing per device within a workout, starting at 1.
    public let seq: UInt64
    /// The creating device's clock when the event happened: the first ordering key, and the time
    /// of events that carry none (rule 9).
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
