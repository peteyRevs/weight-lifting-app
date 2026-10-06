import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 3: `Volume.thousands(in:)` is the number `compact(in:)` prints without its "k"
/// ("24.2" for 24,180 lb), with the same conversion to kilograms; zero reads "0" and every other
/// volume keeps one decimal. Expected strings are rule 34's, written by hand or by `expected(_:in:)`.
@Suite("Volume.thousands (adversarial, F09 S2)", .tags(.domain))
struct VolumeThousandsAdversarialTests {
    struct Row: Sendable, CustomStringConvertible {
        let amount: String
        let text: String

        init(_ amount: String, _ text: String) {
            self.amount = amount
            self.text = text
        }

        var description: String {
            "\(amount) → \(text)"
        }
    }

    /// Whole units either side of every rounding boundary: x49.99 rounds down, x50 rounds up.
    static let boundaries = [
        Row("0.01", "0.0"), Row("40", "0.0"), Row("49", "0.0"), Row("49.99", "0.0"), Row("50", "0.1"),
        Row("99", "0.1"), Row("149.99", "0.1"), Row("150", "0.2"), Row("949", "0.9"), Row("949.99", "0.9"),
        Row("950", "1.0"), Row("999", "1.0"), Row("1000", "1.0"), Row("1049.99", "1.0"), Row("1050", "1.1"),
        Row("9949.99", "9.9"), Row("9950", "10.0"), Row("24180", "24.2"), Row("24149.99", "24.1"),
        Row("24150", "24.2"), Row("41200", "41.2"), Row("24000", "24.0"), Row("99949.99", "99.9"),
        Row("99950", "100.0"), Row("999949", "999.9"), Row("999949.99", "999.9"), Row("999950", "1,000.0"),
        Row("1000000", "1,000.0"), Row("1234567", "1,234.6"), Row("999999949.99", "999,999.9"),
        Row("999999950", "1,000,000.0"), Row("123456789012", "123,456,789.0")
    ]

    static func power(_ exponent: Int, _ significand: Decimal = 1) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: significand)
    }

    static func volume(_ amount: Decimal, in units: Units) -> Volume {
        Volume(weight: Weight(grams: amount * gramsPerUnit(units)), reps: .one)
    }

    /// Rule 34 by hand: the volume in `units` ÷ 1,000 to one decimal, half away from zero, with ','
    /// between thousands and '.' before the decimal; "0" for no volume at all.
    static func expected(_ volume: Volume, in units: Units) -> String {
        guard volume.gramReps != 0 else {
            return "0"
        }
        let tenths = wholeNumber(volume.gramReps / gramsPerUnit(units) / 100)
        var whole = String(tenths.magnitude / 10)
        var grouped = ""
        while whole.count > 3 {
            grouped = "," + String(whole.suffix(3)) + grouped
            whole.removeLast(3)
        }
        return (tenths < 0 ? "-" : "") + whole + grouped + "." + String(tenths.magnitude % 10)
    }

    /// `compact(in:)` without its last character, which must be the "k".
    static func compactNumber(_ volume: Volume, in units: Units) throws -> String {
        let compact = volume.compact(in: units)
        try #require(compact.hasSuffix("k"))
        return String(compact.dropLast())
    }
}

extension VolumeThousandsAdversarialTests {
    @Test("The brief's examples: 24,180 lb reads 24.2, the same volume reads 11.0 in kilograms, zero reads 0.")
    func thousands_briefExamples_matchTheBrief() {
        let week = Self.volume(24180, in: .lb)
        #expect(week.thousands(in: .lb) == "24.2")
        // 24,180 lb × 0.45359237 = 10,967.86 kg.
        #expect(week.thousands(in: .kg) == "11.0")
        #expect(Volume.zero.thousands(in: .lb) == "0")
        #expect(Volume.zero.thousands(in: .kg) == "0")
        #expect(Self.volume(40, in: .lb).thousands(in: .lb) == "0.0")
        #expect(week.compact(in: .lb) == "24.2k")
        #expect(Volume.zero.compact(in: .lb) == "0.0k")
    }

    @Test("Either side of every rounding boundary, in pounds and in kilograms.", arguments: boundaries)
    func thousands_aroundRoundingBoundaries_roundsHalfUp(row: Row) throws {
        for units in Units.allCases {
            let volume = Self.volume(dec(row.amount), in: units)
            #expect(volume.thousands(in: units) == row.text, "\(units)")
            #expect(try volume.thousands(in: units) == Self.compactNumber(volume, in: units), "\(units)")
            #expect(Self.expected(volume, in: units) == row.text, "the hand formatter disagrees with the row")
        }
    }

    @Test("A volume entered in one unit converts before it is rounded, as compact(in:) converts it.")
    func thousands_inTheOtherUnit_convertsThenRounds() {
        // 50 kg is 110.23 lb; 110.23 lb is 49.9995 kg and 110.24 lb is 50.004 kg.
        #expect(Self.volume(50, in: .kg).thousands(in: .lb) == "0.1")
        #expect(Self.volume(dec("110.23"), in: .lb).thousands(in: .kg) == "0.0")
        #expect(Self.volume(dec("110.24"), in: .lb).thousands(in: .kg) == "0.1")
        // 950 lb is 430.9 kg; 2,094.39 lb is 949.9998 kg and 2,094.4 lb is 950.004 kg.
        #expect(Self.volume(950, in: .lb).thousands(in: .kg) == "0.4")
        #expect(Self.volume(dec("2094.39"), in: .lb).thousands(in: .kg) == "0.9")
        #expect(Self.volume(dec("2094.4"), in: .lb).thousands(in: .kg) == "1.0")
        // 22.5 kg is 49.6 lb and 22.7 kg is 50.04 lb.
        #expect(Self.volume(dec("22.5"), in: .kg).thousands(in: .lb) == "0.0")
        #expect(Self.volume(dec("22.7"), in: .kg).thousands(in: .lb) == "0.1")
    }

    @Test("Every way of writing no volume reads 0; the smallest volumes a lifter can store read 0.0.")
    func thousands_zeroAndNearlyZero_readZeroAndZeroPointZero() throws {
        let week = Self.volume(24180, in: .lb)
        let zeros = [
            Volume.zero, Volume(gramReps: 0), Volume(gramReps: Decimal(sign: .plus, exponent: 9, significand: 0)),
            week - week, Volume(weight: .zero, reps: .one), Volume.zero + Volume.zero
        ]
        // ADR-007 stores whole 10⁻⁷ g; 22 kg is 48.5 lb, and −49.99 lb is −22.7 kg.
        let stored = Decimal(sign: .plus, exponent: -7, significand: 1)
        let nearly = [
            Volume(gramReps: stored), Volume(gramReps: -stored), Volume(gramReps: 1), Volume(gramReps: -1),
            Volume(gramReps: Decimal(sign: .plus, exponent: -38, significand: 1)), Self.volume(dec("0.01"), in: .lb),
            Self.volume(22, in: .kg), Self.volume(dec("-49.99"), in: .lb)
        ]
        for units in Units.allCases {
            for zero in zeros {
                #expect(zero.thousands(in: units) == "0")
                #expect(zero.compact(in: units) == "0.0k")
            }
            for volume in nearly {
                #expect(volume.thousands(in: units) == "0.0", "\(volume.gramReps) g in \(units)")
                #expect(try volume.thousands(in: units) == Self.compactNumber(volume, in: units))
            }
        }
    }

    @Test("The smallest volume Decimal holds is not zero, so it reads 0.0 like any other volume under 50 units.")
    func thousands_smallestDecimalVolume_readsZeroPointZero() {
        // Finding F9-S2-1: converting 10⁻¹²⁷ g to a unit underflows Decimal, and the text is then an
        // arbitrary number that changes from call to call, not rule 34's 0.0.
        for units in Units.allCases {
            #expect(Volume(gramReps: .leastNonzeroMagnitude).thousands(in: units) == "0.0", "\(units)")
            #expect(Volume(gramReps: -Decimal.leastNonzeroMagnitude).thousands(in: units) == "0.0", "\(units)")
        }
    }

    @Test("Three values around each of the first 5,000 boundaries agree with compact(in:) and the hand formatter.")
    func thousands_sweepOfBoundaries_agreesWithCompactAndRule34() throws {
        for units in Units.allCases {
            for hundred in 0 ..< 5000 {
                for cents in [4999, 5000, 5001] {
                    let amount = Decimal(hundred * 100) + Decimal(cents) / 100
                    let volume = Self.volume(amount, in: units)
                    let text = volume.thousands(in: units)
                    try #require(text == Self.expected(volume, in: units), "\(amount) \(units) read \(text)")
                    try #require(try text == Self.compactNumber(volume, in: units), "\(amount) \(units) read \(text)")
                }
            }
        }
    }

    @Test(
        "Random weekly totals agree with compact(in:) and the hand formatter in both units.",
        arguments: PropertySeed.all
    )
    func thousands_randomWeeklyTotals_agreeWithCompactAndRule34(seed: PropertySeed) throws {
        var generator = seed.generator
        for _ in 0 ..< 10 {
            let volume = VolumeOracle.randomTotal(using: &generator)
            for units in Units.allCases {
                let text = volume.thousands(in: units)
                #expect(text == Self.expected(volume, in: units), "\(seed): \(volume.gramReps) g in \(units)")
                #expect(try text == Self.compactNumber(volume, in: units), "\(seed): \(volume.gramReps) g in \(units)")
            }
        }
    }

    @Test("Negative and enormous volumes still read as compact(in:) does, and one that is not a number does not trap.")
    func thousands_negativeAndEnormousVolumes_agreeWithCompact() throws {
        let amounts: [Decimal] = [
            -24180, -50, -49, -999_950, Self.power(12), Self.power(15, 9), Self.power(22), Self.power(25),
            -Self.power(40, 7), .greatestFiniteMagnitude, -.greatestFiniteMagnitude
        ]
        for units in Units.allCases {
            for amount in amounts {
                let volume = Volume(gramReps: amount)
                #expect(try volume.thousands(in: units) == Self.compactNumber(volume, in: units), "\(amount) g")
            }
            // No text is specified for a volume that is not a number; asking for it must not trap.
            #expect(!Volume(gramReps: .nan).thousands(in: units).isEmpty)
        }
        #expect(Self.volume(-24180, in: .lb).thousands(in: .lb) == "-24.2")
        // 10⁹ lb is a million thousands: its tenths still fit a 32-bit Int.
        #expect(Self.volume(Self.power(9), in: .lb).thousands(in: .lb) == "1,000,000.0")
    }

    @Test("The text is ASCII digits with ',' and '.', whatever the locale: nothing in it is localised.")
    func thousands_everyOutput_isPlainASCIIInTheSpecShape() throws {
        let shape = #/-?(0|[1-9][0-9]{0,2}(,[0-9]{3})*)\.[0-9]/#
        var generator = SeededGenerator(seed: 20_261_005)
        for _ in 0 ..< 500 {
            let volume = VolumeOracle.randomTotal(using: &generator)
            for units in Units.allCases {
                let text = volume.thousands(in: units)
                #expect(try shape.wholeMatch(in: text) != nil, "\(text)")
                let isASCII = text.unicodeScalars.allSatisfy(\.isASCII)
                #expect(isASCII, "\(text)")
            }
        }
        #expect(Self.volume(1_234_567, in: .lb).thousands(in: .lb) == "1,234.6")
    }
}
