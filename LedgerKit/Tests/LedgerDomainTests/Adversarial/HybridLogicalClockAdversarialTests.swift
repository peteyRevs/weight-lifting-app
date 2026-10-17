import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 3: `HybridLogicalClock`. "A stamp is `max(now, newest stamp seen or
/// sent + 1 ms)`", it never goes back, and it is never not finite. Expected stamps are the formula in `Double`
/// arithmetic, computed here.
@Suite("Adversarial F10 S2 · HybridLogicalClock", .tags(.domain, .property))
struct HybridLogicalClockAdversarialTests {
    static let tick = 0.001
    static let infinity = Date(timeIntervalSinceReferenceDate: .infinity)
    static let notANumber = Date(timeIntervalSinceReferenceDate: .nan)
    static let nonFinite = [infinity, Date(timeIntervalSinceReferenceDate: -.infinity), notANumber]

    static func date(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// A system clock that wanders: small steps both ways, repeats, and jumps of hours and years.
    static func readings(seed: UInt64, count: Int = 400) -> [Date] {
        var random = SplitMix64(seed: seed)
        var now = 800_000_000.0
        let moves: [Double] = [0, 0, 0.0004, 0.001, 0.25, 1, 30, -0.0004, -1, -3600, 86400, -86400, 3.0e8, -3.0e8]
        return (0 ..< count).map { _ in
            now += moves[Int.random(in: 0 ..< moves.count, using: &random)]
            return date(now)
        }
    }

    @Test("Over a wandering clock every stamp is the formula's, and rises", arguments: 0 ..< 50 as Range<UInt64>)
    func stamp_wanderingClock_followsTheFormulaAndRises(seed: UInt64) throws {
        var clock = HybridLogicalClock()
        var newest: Date?
        for now in Self.readings(seed: seed) {
            let expected = newest.map { max(now, $0.addingTimeInterval(Self.tick)) } ?? now
            let given = clock.stamp(now: now)
            let stamp = try #require(given)
            #expect(stamp == expected)
            #expect(newest.map { $0 < stamp } ?? true, "strictly after the one before")
            #expect(stamp >= now && clock.newest == stamp)
            newest = stamp
        }
    }

    @Test("A stamp seen from elsewhere moves the clock forward, never back", arguments: 0 ..< 50 as Range<UInt64>)
    func observe_anyOrder_neverGoesBack(seed: UInt64) throws {
        var clock = HybridLogicalClock()
        var largest: Date?
        for seen in Self.readings(seed: seed, count: 100).shuffled() {
            clock.observe(seen)
            largest = max(largest ?? seen, seen)
            #expect(clock.newest == largest)
        }
        let newest = try #require(largest)
        let next = clock.stamp(now: Self.date(0))
        #expect(next == newest.addingTimeInterval(Self.tick), "after everything it has seen")
    }

    @Test("A stamp that is not finite is never seen, never given and never kept", arguments: nonFinite)
    func nonFiniteStamp_isIgnoredEverywhere(never: Date) {
        #expect(HybridLogicalClock(newest: never).newest == nil)
        var clock = HybridLogicalClock(newest: Self.date(100))
        clock.observe(never)
        #expect(clock.newest == Self.date(100))
        let refused = clock.stamp(now: never)
        #expect(refused == nil, "no finite stamp is also the time of anything")
        #expect(clock.newest == Self.date(100), "and the clock is left as it was")
        let next = clock.stamp(now: Self.date(50))
        #expect(next == Self.date(100).addingTimeInterval(Self.tick))
        var fresh = HybridLogicalClock()
        let first = fresh.stamp(now: never)
        #expect(first == nil && fresh.newest == nil)
    }

    @Test("At the edge of what a Date can hold a stamp stays finite and does not go back")
    func stamp_atTheEdgeOfDouble_staysFinite() throws {
        for edge in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, 1.0e300, -1.0e300] {
            var clock = HybridLogicalClock(newest: Self.date(edge))
            let given = clock.stamp(now: Self.date(0))
            let stamp = try #require(given)
            #expect(stamp.timeIntervalSinceReferenceDate.isFinite)
            #expect(stamp >= max(Self.date(edge), Self.date(0)))
            var fresh = HybridLogicalClock()
            let first = fresh.stamp(now: Self.date(edge))
            #expect(first == Self.date(edge))
        }
    }

    /// The type's documentation: "Above 2⁴⁴ s a millisecond rounds away, so a stamp there equals `newest` and
    /// only `seq` orders the device's envelopes; a host rejects such a stamp on receipt (F17, drift bound)."
    /// Until F17's bound exists, a stored stamp past year 559,000 makes two actions share a stamp.
    @Test("(documents) Below 2⁴⁴ s a repeated clock still rises; from 2⁴⁴ s on the stamp repeats")
    func stamp_pastTwoToTheFortyFour_repeats() {
        let limit = 17_592_186_044_416.0
        var below = HybridLogicalClock(newest: Self.date(limit / 2 + 12345))
        let stamps = [below.stamp(now: Self.date(0)), below.stamp(now: Self.date(0))].compactMap(\.self)
        #expect(stamps.count == 2 && stamps[0] < stamps[1])
        var above = HybridLogicalClock(newest: Self.date(limit))
        let repeated = [above.stamp(now: Self.date(0)), above.stamp(now: Self.date(0))]
        #expect(repeated == [Self.date(limit), Self.date(limit)], "equal, so a peer's envelope there can sort after")
    }

    @Test("Two clocks that saw the same stamps are equal, whatever else differed")
    func equality_isTheNewestStamp() {
        var one = HybridLogicalClock()
        var other = HybridLogicalClock(newest: Self.date(5))
        one.observe(Self.date(3))
        one.observe(Self.date(5))
        other.observe(Self.date(4))
        #expect(one == other && one.hashValue == other.hashValue)
        #expect(HybridLogicalClock() == HybridLogicalClock(newest: Self.infinity))
    }
}
