import Foundation
@testable import LedgerDomain
import Testing

/// An independent check of a percentage, with exact `Decimal` multiplications only (no division,
/// so no quotient is ever cut short).
enum VolumeOracle {
    /// Whether `percent` is `(current − previous) ÷ previous × 100` rounded half away from zero:
    /// `|100·(current − previous) − percent·previous| ≤ |previous| ÷ 2`, and on an exact half
    /// `percent` is the neighbour further from zero.
    static func isRoundedChange(_ percent: Int, from previous: Decimal, to current: Decimal) -> Bool {
        let scaled = 100 * (current - previous)
        let error = scaled - Decimal(percent) * previous
        let twice = 2 * abs(error)
        guard twice == abs(previous) else {
            return twice < abs(previous)
        }
        // The true value is `scaled ÷ previous`; `error ÷ previous` is the true value minus `percent`.
        // Further from zero means the two have opposite signs.
        return (error < 0) != (scaled < 0)
    }

    /// The same number by the brief's formula, in another order of operations, rounded with `NSDecimalRound`.
    static func formula(from previous: Decimal, to current: Decimal) -> Int {
        wholeNumber((current * 100 - previous * 100) / previous)
    }

    /// A week's total: up to 300 sets of quarter-pound or half-kilogram loads, 1 to 30 reps each.
    static func randomTotal(using generator: inout SeededGenerator) -> Volume {
        let quantum = Bool.random(using: &generator) ? gramsPerPound / 4 : 500
        var total = Volume.zero
        for _ in 0 ..< Int.random(in: 1 ... 300, using: &generator) {
            let weight = Weight(grams: randomMultiple(of: quantum, in: 1 ... 4000, using: &generator))
            total += Volume(weight: weight, reps: Reps(clamping: Int.random(in: 1 ... 30, using: &generator)))
        }
        return total
    }
}

@Suite("Volume.percentChange properties and limits (adversarial, F09 S2)", .tags(.domain, .property))
struct PercentChangePropertyAdversarialTests {
    static func power(_ exponent: Int, _ significand: Decimal = 1) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: significand)
    }

    static func change(_ current: Decimal, after previous: Decimal) -> Int? {
        Volume(gramReps: current).percentChange(from: Volume(gramReps: previous))
    }
}

extension PercentChangePropertyAdversarialTests {
    @Test(
        "Random weekly totals agree with the multiplication-only oracle and the formula.",
        arguments: PropertySeed.all
    )
    func percentChange_randomWeeklyTotals_agreeWithTheOracle(seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 25 {
            let previous = VolumeOracle.randomTotal(using: &generator)
            let current = VolumeOracle.randomTotal(using: &generator)
            let percent = try #require(current.percentChange(from: previous), "\(seed)")
            let label = "\(seed): \(current.gramReps) after \(previous.gramReps) gave \(percent)"
            #expect(VolumeOracle.isRoundedChange(percent, from: previous.gramReps, to: current.gramReps), "\(label)")
            #expect(percent == VolumeOracle.formula(from: previous.gramReps, to: current.gramReps), "\(label)")
            #expect(previous.percentChange(from: previous) == 0)
        }
    }

    @Test("One stored unit (10⁻⁷ g) either side of an exact half decides the rounding.", arguments: PropertySeed.all)
    func percentChange_oneStoredUnitFromAHalf_isDecidedExactly(seed: PropertySeed) {
        var generator = seed.generator
        let unit = Self.power(-7)
        for _ in 0 ..< 25 {
            // previous = 200·m units, so (2·step + 1)·m units are exactly step + ½ percent of it.
            let count = Decimal(Int64.random(in: 2 ... 100_000_000_000_000_000, using: &generator))
            let step = Int.random(in: -120 ... 400, using: &generator)
            let nudge = Int.random(in: -1 ... 1, using: &generator)
            let sign: Decimal = Bool.random(using: &generator) ? 1 : -1
            let previous = sign * 200 * count * unit
            let current = previous + sign * (Decimal(2 * step + 1) * count + Decimal(nudge)) * unit
            let half = step >= 0 ? step + 1 : step
            let expected = nudge > 0 ? step + 1 : nudge < 0 ? step : half
            let label = "\(seed): \(current) after \(previous)"
            #expect(Self.change(current, after: previous) == expected, "\(label)")
            #expect(
                VolumeOracle.isRoundedChange(expected, from: previous, to: current),
                "the oracle disagrees: \(label)"
            )
        }
    }

    @Test("Random exact decimals of any sign and scale agree with the oracle.", arguments: PropertySeed.all)
    func percentChange_randomDecimals_agreeWithTheOracle(seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 25 {
            let digits = Int.random(in: 1 ... 16, using: &generator)
            let limit = (0 ..< digits).reduce(Int64(1)) { product, _ in product * 10 }
            let scale = Int.random(in: -7 ... 3, using: &generator)
            let previous = Self.power(scale, Decimal(Int64.random(in: 1 ... limit, using: &generator)))
                * (Bool.random(using: &generator) ? 1 : -1)
            let current = Self.power(scale, Decimal(Int64.random(in: -limit ... limit, using: &generator)))
            let percent = try #require(Self.change(current, after: previous), "\(seed)")
            // At most 2 × 10¹⁸ percent: inside a 64-bit Int. A 32-bit Int (arm64_32) clamps sooner.
            guard percent != Int.max, percent != Int.min else {
                continue
            }
            #expect(
                VolumeOracle.isRoundedChange(percent, from: previous, to: current),
                "\(seed): \(current) after \(previous) gave \(percent)"
            )
        }
    }

    @Test("A tiny volume after a huge one is −100, and nothing overflows on the way.")
    func percentChange_tinyAfterHuge_isMinusOneHundred() {
        let huge = [Self.power(12), Self.power(30), Self.power(100), Self.power(126), Decimal.greatestFiniteMagnitude]
        let tiny = [
            Self.power(-7),
            Self.power(-30),
            Self.power(-100),
            Self.power(-127),
            Decimal.leastNonzeroMagnitude,
            0
        ]
        for previous in huge {
            for current in tiny {
                #expect(Self.change(current, after: previous) == -100, "\(current) after \(previous)")
                #expect(Self.change(-current, after: -previous) == -100, "\(-current) after \(-previous)")
            }
            #expect(Self.change(previous, after: previous) == 0)
            #expect(Self.change(previous * 2, after: previous) == (previous == .greatestFiniteMagnitude ? nil : 100))
        }
        for volume in tiny where volume != 0 {
            #expect(Self.change(volume, after: volume) == 0)
            #expect(Self.change(volume * 2, after: volume) == 100)
            #expect(Self.change(0, after: volume) == -100)
        }
    }

    @Test("A change too large for Int is clamped to Int.max or Int.min, as the declaration says.")
    func percentChange_hugeAfterTiny_isClamped() {
        for exponent in [17, 18, 19, 20, 25, 30, 38, 39, 60, 100, 124] {
            let huge = Self.power(exponent)
            #expect(Self.change(huge, after: 1) == Int.max, "10^\(exponent) after 1")
            #expect(Self.change(-huge, after: 1) == Int.min, "−10^\(exponent) after 1")
            #expect(Self.change(huge, after: -1) == Int.min, "10^\(exponent) after −1")
            #expect(Self.change(1, after: Self.power(-exponent)) == Int.max, "1 after 10^−\(exponent)")
        }
    }

    @Test("At the edges of Int the percentage is exact up to the last value and clamped one past it.")
    func percentChange_atTheEdgesOfInt_isExactThenClamped() {
        // After 100, a volume of 100 + n is a change of exactly n percent.
        let most = Decimal(Int.max)
        let least = Decimal(Int.min)
        #expect(Self.change(100 + most, after: 100) == Int.max)
        #expect(Self.change(100 + most - 1, after: 100) == Int.max - 1)
        #expect(Self.change(100 + most + 1, after: 100) == Int.max)
        #expect(Self.change(100 + most * 3, after: 100) == Int.max)
        #expect(Self.change(100 + least, after: 100) == Int.min)
        #expect(Self.change(100 + least + 1, after: 100) == Int.min + 1)
        #expect(Self.change(100 + least - 1, after: 100) == Int.min)
        #expect(Self.change(100 + least * 3, after: 100) == Int.min)
        // After 200, 200 + (2n − 1) is n − ½ percent: half away from zero is n.
        #expect(Self.change(200 + 2 * most - 1, after: 200) == Int.max)
        #expect(Self.change(200 + 2 * most - 3, after: 200) == Int.max - 1)
        #expect(Self.change(200 + 2 * least + 1, after: 200) == Int.min)
        #expect(Self.change(200 + 2 * least + 3, after: 200) == Int.min + 1)
        #expect(Self.change(Decimal(Int.max / 2) + 100, after: 100) == Int.max / 2)
        #expect(Self.change(Decimal(Int.min / 2) + 100, after: 100) == Int.min / 2)
    }

    @Test("Volumes at the limits of Decimal never trap, and give a number only when one exists.")
    func percentChange_atTheLimitsOfDecimal_doesNotTrap() {
        let most = Decimal.greatestFiniteMagnitude
        let least = Decimal.leastNonzeroMagnitude
        #expect(Self.change(most, after: most) == 0)
        #expect(Self.change(-most, after: -most) == 0)
        #expect(Self.change(least, after: least) == 0)
        #expect(Self.change(least, after: most) == -100)
        // The true change is −200%, but 2 × the largest Decimal is not a Decimal: nil or −200, never a trap.
        #expect([nil, -200].contains(Self.change(-most, after: most)))
        #expect([nil, -200].contains(Self.change(most, after: -most)))
        // About 10²⁹⁴ percent: past Decimal itself, so the declaration's nil, or its clamp.
        #expect([nil, Int.max].contains(Self.change(most, after: least)))
        #expect([nil, Int.min].contains(Self.change(-most, after: least)))
        #expect([nil, Int.max].contains(Self.change(Self.power(100), after: Self.power(-100))))
        // 10¹²⁸ percent is a Decimal, but Foundation's × 100 already overflows there (finding F9-S2-2):
        // the declaration's "about 10¹⁶⁵" is nearer 10¹²⁷.
        #expect([nil, Int.max].contains(Self.change(Self.power(126), after: 1)))
        #expect([nil, Int.min].contains(Self.change(-Self.power(126), after: 1)))
    }

    @Test("Totals that fill all 38 digits of a Decimal, and its widest significand, are rounded on the exact value.")
    func percentChange_thirtyEightDigitTotals_roundOnTheExactValue() throws {
        // previous = 2 × 10³⁷; half a percent of it is 10³⁵, and one unit less is not a half.
        let previous = try #require(Decimal(string: "20000000000000000000000000000000000000"))
        let half = Self.power(35)
        #expect(Self.change(previous + half, after: previous) == 1)
        #expect(Self.change(previous + half - 1, after: previous) == 0)
        #expect(Self.change(previous + half + 1, after: previous) == 1)
        #expect(Self.change(previous - half, after: previous) == -1)
        #expect(Self.change(previous - half + 1, after: previous) == 0)
        #expect(Self.change(previous - half - 1, after: previous) == -1)
        #expect(Self.change(previous + 3 * half, after: previous) == 2)
        #expect(Self.change(previous + 3 * half - 1, after: previous) == 1)
        #expect(Self.change(previous - 5 * half, after: previous) == -3)
        #expect(Self.change(previous - 5 * half + 1, after: previous) == -2)
        // previous = 2 × 10³⁸ ± 1: a rise of 10³⁶ is 2.5 × 10⁻³⁹ percent short of a half, or past it,
        // which only the 39th digit of the quotient shows.
        let wide = try #require(Decimal(string: "200000000000000000000000000000000000000"))
        #expect(Self.change(wide + 1 + Self.power(36), after: wide + 1) == 0)
        #expect(Self.change(wide + 1 - Self.power(36), after: wide + 1) == 0)
        #expect(Self.change(wide - 1 + Self.power(36), after: wide - 1) == 1)
        #expect(Self.change(wide - 1 - Self.power(36), after: wide - 1) == -1)
        // The largest significand a Decimal holds, 2¹²⁸ − 1, and its neighbour.
        let widest = try #require(Decimal(string: "340282366920938463463374607431768211455"))
        #expect(Self.change(widest, after: widest - 1) == 0)
        // Foundation itself divides −1 by 2¹²⁸ − 1 to "not a number", so nil is allowed here.
        #expect([nil, 0].contains(Self.change(widest - 1, after: widest)))
        #expect(Self.change(widest, after: Self.power(38)) == 240)
        #expect(Self.change(Self.power(38), after: widest) == -71)
    }
}
