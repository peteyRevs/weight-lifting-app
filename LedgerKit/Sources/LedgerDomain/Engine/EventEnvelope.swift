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
    /// The ordering stamp: the first key of `<`, and nothing else. The reducer never reads it as the
    /// time of an action (the clock rule on `WorkoutEvent`); it only bounds payload times
    /// (`isWellFormed`).
    ///
    /// **Precondition (ADR-004 amendment, hybrid logical clock):** the host (F10/F17), not the reducer,
    /// stamps it as `max(now, newest wallClock seen or sent + 1 ms)`. An envelope then sorts after
    /// every envelope its device had sent or received, which keeps each device's `seq` order and causal
    /// order under clock skew. Raw clocks still converge, but on stamp order, not on what happened. On
    /// launch the host recovers `newest` from its store before it stamps anything.
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

// MARK: - Well-formedness (F04 fix round 2)

public extension EventEnvelope {
    /// How far a payload time may lie from its envelope's `wallClock`: 24 hours.
    ///
    /// Both clocks read the same moment on one device, so a real envelope sits within seconds of its
    /// stamp. The window is generous on purpose. The hybrid logical clock drags `wallClock` ahead of the
    /// device's clock by a peer's skew, and a device may record an action long after it happened, for
    /// example a finish ended at the last set after hours of "Still lifting?" (decision #8). Only an
    /// absurd or non-finite time falls outside it, which is all it is for: such a time would trap
    /// `Duration` arithmetic or break `==` (NaN).
    static let payloadTimeWindow = Duration.seconds(24 * 60 * 60)

    /// Whether `WorkoutEngine` may apply this envelope. A malformed envelope is a no-op for `reduce`
    /// and `replay`: no state change and no effects. It stays stored, like any envelope, so every
    /// device's log still agrees.
    ///
    /// An envelope is malformed when:
    /// - its `wallClock` is not finite;
    /// - any date it carries (`doneAt`, a set's `doneAt`, `restStarted.endsAt`, `tappedAt`, `endedAt`,
    ///   and in a `started` snapshot `startedAt`, `endedAt`, the rest's `endsAt` and every set's
    ///   `doneAt`) lies more than `payloadTimeWindow` from `wallClock`; a non-finite date never lies
    ///   within it;
    /// - a rest length (`restStarted.total`, `restExtended.amount`, a snapshot rest's `total`) is
    ///   negative or beyond `WorkoutEngine.longestRest`;
    /// - a `started` snapshot's rest ends more than `longestRest` after the snapshot's `startedAt`.
    var isWellFormed: Bool {
        guard wallClock.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        switch event {
        case let .started(snapshot):
            return isWellFormed(snapshot)
        case let .setLogged(_, _, _, _, doneAt):
            return isNear(doneAt)
        case let .setAdded(_, set):
            return set.doneAt.map(isNear) ?? true
        case let .restStarted(endsAt, total):
            return isNear(endsAt) && Self.isRestLength(total)
        case let .restExtended(amount, _, tappedAt):
            return isNear(tappedAt) && Self.isRestLength(amount)
        case let .finished(endedAt), let .discarded(endedAt):
            return isNear(endedAt)
        case .exerciseSelected, .setUnlogged, .setTargetChanged, .allSetsRepeated, .exerciseSwapped, .restSkipped:
            return true
        }
    }

    /// Whether `date` lies within `payloadTimeWindow` of `wallClock`. NaN fails every comparison.
    private func isNear(_ date: Date) -> Bool {
        abs(date.timeIntervalSince(wallClock)) <= Self.payloadTimeWindow / .seconds(1)
    }

    private static func isRestLength(_ length: Duration) -> Bool {
        (.zero ... WorkoutEngine.longestRest).contains(length)
    }

    /// The `started` clauses of `isWellFormed`: every date near the stamp, and a rest the engine
    /// could itself hold.
    private func isWellFormed(_ snapshot: WorkoutState) -> Bool {
        let setDates = snapshot.exercises.flatMap { $0.sets.compactMap(\.doneAt) }
        let dates = [snapshot.startedAt] + [snapshot.endedAt, snapshot.rest?.endsAt].compactMap(\.self) + setDates
        guard dates.allSatisfy(isNear) else {
            return false
        }
        guard let rest = snapshot.rest else {
            return true
        }
        let latestEnd = snapshot.startedAt.addingTimeInterval(WorkoutEngine.longestRest / .seconds(1))
        return Self.isRestLength(rest.total) && rest.endsAt <= latestEnd
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
