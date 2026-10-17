import Foundation

/// ADR-004's hybrid logical clock (amendment 2026-09-29): what a host stamps `EventEnvelope.wallClock` with.
///
///     stamp = max(now, newest stamp seen or sent + 1 ms)
///
/// An envelope stamped this way sorts after every envelope its device had stored, sent or received, so
/// `WorkoutEngine.replay` folds a device's actions in the order they happened even when its system clock runs
/// behind a peer's or steps back (F04 findings 6 and 12), while the stamp stays close to real time.
///
/// The clock holds one value, `newest`. It does not survive a relaunch by itself: before a host stamps anything
/// it restores `newest` from its store (`WorkoutEventStore.newestWallClock()`; ADR-004, "Recovery on launch").
public struct HybridLogicalClock: Hashable, Sendable {
    /// The gap that puts a stamp after `newest` when the system clock has not passed it.
    public static let tick: TimeInterval = 0.001

    /// The newest stamp this device has stored, sent or seen; `nil` before the first. Always finite.
    public private(set) var newest: Date?

    /// A clock that has seen `newest`; one that is not finite counts as none.
    public init(newest: Date? = nil) {
        if let newest {
            observe(newest)
        }
    }

    /// Notes a stamp this device stored or received: `newest` never goes back. A stamp that is not finite is
    /// ignored, because every later stamp would be at least as large and `WorkoutEngine` drops an envelope
    /// whose stamp is not finite (ADR-004, "Recovery skips only non-finite stamps").
    public mutating func observe(_ stamp: Date) {
        guard stamp.timeIntervalSinceReferenceDate.isFinite else {
            return
        }
        newest = max(newest ?? stamp, stamp)
    }

    /// The stamp for an envelope this device creates when its system clock reads `now`:
    /// `max(now, newest + 1 ms)`, which becomes `newest`.
    ///
    /// `nil`, leaving the clock as it was, when `now` is not a finite time: there is then no finite stamp
    /// that is also the time of anything. The host refuses the action (`LocalWorkoutSessionActor`); it never
    /// stores a stamp the engine would ignore.
    ///
    /// Above 2⁴⁴ s a millisecond rounds away, so a stamp there equals `newest` and only `seq` orders the
    /// device's envelopes; a host rejects such a stamp on receipt (F17, drift bound).
    public mutating func stamp(now: Date) -> Date? {
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            return nil
        }
        let stamp = newest.map { max(now, $0.addingTimeInterval(Self.tick)) } ?? now
        newest = stamp
        return stamp
    }
}
