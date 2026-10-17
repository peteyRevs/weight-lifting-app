import Foundation
import LedgerDomain
import Testing

/// ADR-004's hybrid logical clock (amendment 2026-09-29): `stamp = max(now, newest + 1 ms)`. F10 S2
/// criterion 3.
@Suite("HybridLogicalClock", .tags(.domain))
struct HybridLogicalClockTests {
    static let tick = HybridLogicalClock.tick
    static let now = Fixtures.now
    static let notFinite: [Double] = [.nan, .infinity, -.infinity]

    @Test("The first stamp is the system clock's time, and becomes the newest")
    func stamp_first_isNow() {
        var clock = HybridLogicalClock()
        #expect(clock.newest == nil)
        #expect(clock.stamp(now: Self.now) == Self.now)
        #expect(clock.newest == Self.now)
    }

    @Test("A system clock ahead of the newest stamp gives its own time")
    func stamp_clockAhead_isNow() {
        var clock = HybridLogicalClock(newest: Self.now)
        let later = Self.now.addingTimeInterval(5)
        #expect(clock.stamp(now: later) == later)
        #expect(clock.newest == later)
    }

    @Test(
        "A system clock at or behind the newest stamp gives one millisecond after it",
        arguments: [0, -0.0005, -1, -31_536_000] as [Double]
    )
    func stamp_clockBehind_isOneTickAfterNewest(behind: Double) {
        var clock = HybridLogicalClock(newest: Self.now)
        let expected = Self.now.addingTimeInterval(Self.tick)
        #expect(clock.stamp(now: Self.now.addingTimeInterval(behind)) == expected)
        #expect(clock.newest == expected)
        #expect(clock.stamp(now: Self.now.addingTimeInterval(behind)) == expected.addingTimeInterval(Self.tick))
    }

    @Test("Observing a stamp never moves the newest back")
    func observe_onlyRaises() {
        var clock = HybridLogicalClock()
        clock.observe(Self.now)
        clock.observe(Self.now.addingTimeInterval(-60))
        #expect(clock.newest == Self.now)
        clock.observe(Self.now.addingTimeInterval(60))
        #expect(clock.newest == Self.now.addingTimeInterval(60))
        // A stamp made after a peer's sorts after it, whatever this device's clock reads.
        #expect(clock.stamp(now: Self.now) == Self.now.addingTimeInterval(60 + Self.tick))
    }

    @Test("A stamp that is not finite is never observed", arguments: notFinite)
    func observe_ignoresNonFiniteStamps(seconds: Double) {
        let stamp = Date(timeIntervalSinceReferenceDate: seconds)
        var clock = HybridLogicalClock(newest: stamp)
        #expect(clock.newest == nil)
        clock.observe(Self.now)
        clock.observe(stamp)
        #expect(clock.newest == Self.now)
        #expect(clock == HybridLogicalClock(newest: Self.now))
    }

    @Test("A system clock that is not finite gives no stamp and leaves the clock as it was", arguments: notFinite)
    func stamp_nonFiniteNow_isNil(seconds: Double) {
        let reading = Date(timeIntervalSinceReferenceDate: seconds)
        var fresh = HybridLogicalClock()
        #expect(fresh.stamp(now: reading) == nil)
        #expect(fresh.newest == nil)
        var running = HybridLogicalClock(newest: Self.now)
        #expect(running.stamp(now: reading) == nil)
        #expect(running.newest == Self.now)
    }

    @Test("Stamps are finite and strictly increase, whatever a seeded system clock does", arguments: 0 ..< 20)
    func stamps_strictlyIncrease(seed: UInt64) throws {
        var random = SeededGenerator(seed: seed)
        var clock = HybridLogicalClock()
        var reading = Self.now
        var last: Date?
        for _ in 0 ..< 200 {
            // Mostly forward by up to two minutes; one time in four the clock steps back by up to an hour.
            let step = Bool.random(using: &random) || Bool.random(using: &random)
                ? Double.random(in: 0 ... 120, using: &random)
                : -Double.random(in: 0 ... 3600, using: &random)
            reading = reading.addingTimeInterval(step)
            let stamped = clock.stamp(now: reading)
            let stamp = try #require(stamped)
            #expect(stamp >= reading && stamp.timeIntervalSinceReferenceDate.isFinite)
            if let last {
                #expect(stamp > last)
            }
            last = stamp
        }
    }

    @Test("Above 2⁴⁴ s a millisecond rounds away: the stamp is the newest again, and seq alone orders")
    func stamp_atAnAbsurdMagnitude_doesNotAdvance() {
        let absurd = Date(timeIntervalSinceReferenceDate: 0x1p53)
        var clock = HybridLogicalClock(newest: absurd)
        #expect(clock.stamp(now: Self.now) == absurd)
        #expect(clock.newest == absurd)
        let largest = Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)
        clock.observe(largest)
        #expect(clock.stamp(now: Self.now) == largest)
    }
}
