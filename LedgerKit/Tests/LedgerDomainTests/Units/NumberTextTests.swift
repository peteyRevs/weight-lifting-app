import Foundation
@testable import LedgerDomain
import Testing

/// `Decimal.roundedToInt(_:)`, the rounding every whole-number domain text goes through
/// (`Units/NumberText.swift`). F09 S2 fix round 1, finding F9-S2-1: a value that is not a number
/// rounds to 0, where it used to read as an arbitrary number.
@Suite("NumberText", .tags(.domain))
struct NumberTextTests {
    static let rules: [FloatingPointRoundingRule] = [
        .toNearestOrAwayFromZero, .toNearestOrEven, .up, .down, .towardZero, .awayFromZero
    ]

    static func power(_ exponent: Int, _ significand: Decimal = 1) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: significand)
    }

    @Test("A value that is not a number rounds to 0, under every rule")
    func roundedToInt_notANumber_isZero() throws {
        // `Decimal` has no quotient this small, and gives NaN for it: 10⁻¹²⁷ g in kilograms.
        let tooSmall = Decimal.leastNonzeroMagnitude / 1000
        try #require(tooSmall.isNaN)
        for rule in Self.rules {
            #expect(Decimal.nan.roundedToInt(rule) == 0, "\(rule)")
            #expect(tooSmall.roundedToInt(rule) == 0, "\(rule)")
            #expect((Decimal(1) / 0).roundedToInt(rule) == 0, "\(rule)")
        }
    }

    @Test("A number rounds as before: half away from zero unless another rule is given")
    func roundedToInt_numbers_roundByTheRule() {
        #expect(dec("2.5").roundedToInt() == 3)
        #expect(dec("-2.5").roundedToInt() == -3)
        #expect(dec("2.49").roundedToInt() == 2)
        #expect(dec("-0.4").roundedToInt() == 0)
        #expect(dec("2.5").roundedToInt(.toNearestOrEven) == 2)
        #expect(dec("2.9").roundedToInt(.down) == 2)
        #expect(dec("-2.1").roundedToInt(.down) == -3)
        #expect(dec("-2.9").roundedToInt(.towardZero) == -2)
        #expect(dec("2.1").roundedToInt(.up) == 3)
        #expect(Decimal(0).roundedToInt() == 0)
        #expect(Self.power(-120).roundedToInt() == 0)
        #expect(Decimal(Int.max).roundedToInt() == Int.max)
        #expect(Decimal(Int.min).roundedToInt() == Int.min)
    }

    @Test("A weight too small to show, or one that is not a number, is 0 whole units")
    func wholeValue_weightTooSmallToShow_isZero() {
        let tooSmall = [.leastNonzeroMagnitude, -.leastNonzeroMagnitude, Self.power(-100), Self.power(-89)]
        for grams in tooSmall {
            for units in Units.allCases {
                #expect(Weight(grams: grams).wholeValue(in: units) == 0, "\(grams) g in \(units)")
            }
        }
        #expect(Weight(grams: .nan).wholeValue(in: .lb) == 0)
    }

    @Test("A plate too heavy to count against the load is left off the bar")
    func perSide_plateTooHeavyToCount_isLeftOff() throws {
        // Per side 10⁻³⁰ g: against a plate of 10¹⁰⁰ g the count, 10⁻¹³⁰, is a quotient Decimal cannot hold.
        let light = Weight(grams: Self.power(-30))
        let heavy = Weight(grams: Self.power(100))
        try #require((light.grams / heavy.grams).isNaN)
        let inventory = PlateInventory(bar: .zero, plates: [heavy, light])
        let breakdown = try #require(PlateMath.perSide(load: light + light, inventory: inventory))
        #expect(breakdown.perSide == [PlateMath.PlateCount(plate: light, count: 1)])
        #expect(breakdown.remainder == .zero)
    }
}
