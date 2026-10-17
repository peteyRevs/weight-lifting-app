import Foundation

/// A running rest countdown, anchored to wall-clock time (ADR-004: `endsAt` is absolute, so
/// phone and watch show the same number without exchanging ticks).
public struct RestTimer: Hashable, Codable, Sendable {
    public var endsAt: Date
    /// The full rest length, for the ring's scale (rule 23: "+30s" grows both).
    public var total: Duration

    public init(endsAt: Date, total: Duration) {
        self.endsAt = endsAt
        self.total = total
    }

    /// Rule 23: time left at `now`, never negative. It saturates at 2^63 s (`Double(Int64.max)`), and
    /// an interval that is not finite (a non-finite `endsAt` or `now`, NaN included) means no rest left:
    /// zero. `Duration.seconds` traps on a non-finite or out-of-range interval, and the dates can come
    /// from anywhere a `RestTimer` decodes (F04 fix round 2).
    public func remaining(at now: Date) -> Duration {
        let left = endsAt.timeIntervalSince(now)
        guard left.isFinite else {
            return .zero
        }
        return .seconds(min(max(0, left), Double(Int64.max)))
    }

    /// The share of the rest still to go at `now`, in 0…1 (the ring's fill); 0 when `total` is not
    /// positive or no rest is left, which includes every non-finite case of `remaining(at:)`.
    public func fraction(at now: Date) -> Double {
        guard total > .zero else {
            return 0
        }
        return min(1, remaining(at: now) / total)
    }

    /// How long after `now` the countdown's text next changes: the time to the next whole second left
    /// (`ClockText.remaining` rounds up, so 74.3 s left reads "1:15" for another 0.3 s), a full second when
    /// a whole number of seconds is left, and nil when no time is left. What ticks a screen waits this long
    /// and then reads the clock again; it never counts the seconds itself.
    public func nextTick(after now: Date) -> Duration? {
        let left = remaining(at: now)
        guard left > .zero else {
            return nil
        }
        let fraction = Duration(secondsComponent: 0, attosecondsComponent: left.components.attoseconds)
        return fraction > .zero ? fraction : .seconds(1)
    }
}
