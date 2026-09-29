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
    /// time of an action and never compares a payload time with it (the clock rule on `WorkoutEvent`);
    /// `isWellFormed` only requires it to be finite.
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

// MARK: - Well-formedness (F04 fix round 2; re-plan 2026-09-29)

public extension EventEnvelope {
    /// Whether `WorkoutEngine` may apply this envelope. A malformed envelope is a no-op for `reduce`
    /// and `replay`: no state change and no effects. It stays stored, like any envelope, so every
    /// device's log still agrees.
    ///
    /// An envelope is malformed only when:
    /// - a date it carries is not finite: its `wallClock`, a payload date (`doneAt`, a set's `doneAt`,
    ///   `restStarted.endsAt`, `tappedAt`, `endedAt`), or any date in a `started` snapshot (`startedAt`,
    ///   `endedAt`, the rest's `endsAt`, every set's `doneAt` and every `lastPerformance.date`);
    /// - a rest length (`restStarted.total`, `restExtended.amount`, a snapshot rest's `total`) is
    ///   negative or beyond `WorkoutEngine.longestRest`.
    ///
    /// There is no time window (Pete, 2026-09-29): a finite date is accepted however far it lies from
    /// `wallClock` or from any other date, such as a "Still lifting?" finish days after the last set
    /// (F23 criterion 6). The engine's arithmetic saturates on such dates rather than trap.
    var isWellFormed: Bool {
        wallClock.isFinite && event.isWellFormed
    }
}

private extension WorkoutEvent {
    /// Every date it carries is finite, and every rest length lies in `0 ... WorkoutEngine.longestRest`.
    var isWellFormed: Bool {
        switch self {
        case let .started(snapshot):
            let dates = [snapshot.startedAt, snapshot.endedAt, snapshot.rest?.endsAt].compactMap(\.self)
                + snapshot.exercises.flatMap(\.sets).compactMap(\.doneAt)
                + snapshot.exercises.compactMap(\.lastPerformance?.date)
            return dates.allSatisfy(\.isFinite) && snapshot.rest.map(\.total.isRestLength) ?? true
        case let .setLogged(_, _, _, _, date), let .finished(date), let .discarded(date):
            return date.isFinite
        case let .setAdded(_, set):
            return set.doneAt?.isFinite ?? true
        case let .restStarted(date, length), let .restExtended(length, _, date):
            return date.isFinite && length.isRestLength
        case .exerciseSelected, .setUnlogged, .setTargetChanged, .allSetsRepeated, .exerciseSwapped, .restSkipped:
            return true
        }
    }
}

private extension Date {
    var isFinite: Bool {
        timeIntervalSinceReferenceDate.isFinite
    }
}

private extension Duration {
    var isRestLength: Bool {
        (.zero ... WorkoutEngine.longestRest).contains(self)
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
