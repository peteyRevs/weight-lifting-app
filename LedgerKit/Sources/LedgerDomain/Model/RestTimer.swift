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

    /// Rule 23: time left at `now`, never negative.
    public func remaining(at now: Date) -> Duration {
        .seconds(max(0, endsAt.timeIntervalSince(now)))
    }

    /// The share of the rest still to go at `now`, in 0…1 (the ring's fill); 0 when `total` is not positive.
    public func fraction(at now: Date) -> Double {
        guard total > .zero else {
            return 0
        }
        return min(1, remaining(at: now) / total)
    }
}
