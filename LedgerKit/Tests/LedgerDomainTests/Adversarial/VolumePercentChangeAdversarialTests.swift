import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 2: `Volume.percentChange(from:)` is `(self − previous) ÷ previous × 100` in
/// whole percent, rounded half away from zero, exact, `nil` for a zero previous volume, and never
/// traps. Expected values are the brief's, hand arithmetic, or `VolumeOracle`'s.
@Suite("Volume.percentChange (adversarial, F09 S2)", .tags(.domain))
struct VolumePercentChangeAdversarialTests {
    struct Row: Sendable, CustomStringConvertible {
        let previous: String
        let current: String
        let percent: Int

        init(_ previous: String, _ current: String, _ percent: Int) {
            self.previous = previous
            self.current = current
            self.percent = percent
        }

        var description: String {
            "\(current) after \(previous) → \(percent)%"
        }
    }

    static let briefRows = [
        Row("22400", "24180", 8), Row("22400", "21728", -3), Row("22400", "22400", 0), Row("185", "185", 0)
    ]

    /// Exact halves, and the hundredth of a unit either side of them.
    static let tieRows = [
        Row("200", "201", 1), Row("200", "199", -1), Row("200", "203", 2), Row("200", "197", -2),
        Row("200", "205", 3), Row("200", "195", -3), Row("200", "249", 25), Row("200", "151", -25),
        Row("22400", "22512", 1), Row("22400", "22288", -1), Row("22400", "22960", 3), Row("22400", "21840", -3),
        Row("1000", "1005", 1), Row("1000", "995", -1), Row("1000", "1004.99", 0), Row("1000", "1005.01", 1),
        Row("1000", "995.01", 0), Row("1000", "994.99", -1), Row("1000", "1014.99", 1), Row("1000", "1015", 2),
        Row("1000", "985", -2), Row("1000", "985.01", -1), Row("0.25", "0.25125", 1), Row("0.25", "0.24875", -1),
        Row("22400", "0", -100), Row("22400", "44800", 100), Row("22400", "22511.99", 0), Row("22400", "67200", 200)
    ]

    static func volume(_ text: String, in units: Units) -> Volume {
        Volume(weight: units == .lb ? pounds(text) : kilos(text), reps: .one)
    }
}

extension VolumePercentChangeAdversarialTests {
    @Test("The brief's examples: 24,180 after 22,400 is 8, 21,728 is −3, equal volumes are 0.", arguments: briefRows)
    func percentChange_briefExamples_matchTheBrief(row: Row) {
        for units in Units.allCases {
            let change = Self.volume(row.current, in: units).percentChange(from: Self.volume(row.previous, in: units))
            #expect(change == row.percent, "\(units)")
        }
        let grams = Volume(gramReps: dec(row.current)).percentChange(from: Volume(gramReps: dec(row.previous)))
        #expect(grams == row.percent)
    }

    @Test(
        "An exact half rounds away from zero, up for a rise and down for a fall, in pounds and kilograms.",
        arguments: tieRows
    )
    func percentChange_exactHalves_roundAwayFromZero(row: Row) {
        for units in Units.allCases {
            let change = Self.volume(row.current, in: units).percentChange(from: Self.volume(row.previous, in: units))
            #expect(change == row.percent, "\(units)")
        }
    }

    @Test("A zero previous volume has no percentage, whatever the current volume is.")
    func percentChange_zeroPrevious_isNil() {
        let currents = [
            Volume.zero, Self.volume("24180", in: .lb), Volume(gramReps: -5),
            Volume(gramReps: .greatestFiniteMagnitude),
            Volume(gramReps: .leastNonzeroMagnitude), Volume(gramReps: .nan)
        ]
        let zeros = [
            Volume.zero, Volume(gramReps: Decimal(sign: .plus, exponent: 12, significand: 0)),
            Self.volume("185", in: .lb) - Self.volume("185", in: .lb), Volume(weight: .zero, reps: .one)
        ]
        for current in currents {
            for zero in zeros {
                #expect(current.percentChange(from: zero) == nil, "\(current.gramReps) after \(zero.gramReps)")
            }
        }
    }

    @Test("Every exact half from −5.5% to +5.5%, on 1,000 pound and 1,000 kilogram totals, rounds away from zero.")
    func percentChange_everyHalfOnEnterableTotals_roundsAwayFromZero() {
        for units in Units.allCases {
            for total in stride(from: 2, through: 2000, by: 2) {
                let previous = Decimal(total)
                for step in -6 ... 5 {
                    // The change is (2·step + 1) ÷ 2 percent of `previous`: a whole number of hundredths.
                    let current = previous + previous * Decimal(2 * step + 1) / 200
                    let before = Volume(weight: Weight(grams: previous * gramsPerUnit(units)), reps: .one)
                    let after = Volume(weight: Weight(grams: current * gramsPerUnit(units)), reps: .one)
                    let expected = step >= 0 ? step + 1 : step
                    #expect(after.percentChange(from: before) == expected, "\(current) after \(previous) \(units)")
                }
            }
        }
    }

    @Test("Totals summed set by set in pounds, which are never whole grams, still tie exactly (ADR-007).")
    func percentChange_summedPoundSets_tieExactly() throws {
        // 200 sets of 185 lb × 5 are 185,000 lb; 37 more sets of 5 lb × 5 add 925 lb, exactly 0.5%.
        let heavy = try Volume(weight: pounds("185"), reps: Fixtures.reps(5))
        let light = try Volume(weight: pounds("5"), reps: Fixtures.reps(5))
        let previous = (0 ..< 200).reduce(Volume.zero) { sum, _ in sum + heavy }
        let extra = (0 ..< 37).reduce(Volume.zero) { sum, _ in sum + light }
        #expect(previous.formatted(in: .lb) == "185,000")
        #expect((previous + extra).percentChange(from: previous) == 1)
        #expect((previous - extra).percentChange(from: previous) == -1)
        let hundredth = Volume(weight: pounds("0.01"), reps: .one)
        #expect((previous + extra - hundredth).percentChange(from: previous) == 0)
        #expect((previous - extra + hundredth).percentChange(from: previous) == 0)
        #expect((previous + extra + hundredth).percentChange(from: previous) == 1)
        // 2.5% of 185,000 lb is 4,625 lb: 185 sets of 5 lb × 5.
        let more = (0 ..< 185).reduce(Volume.zero) { sum, _ in sum + light }
        #expect((previous + more).percentChange(from: previous) == 3)
        #expect((previous - more).percentChange(from: previous) == -3)
    }

    @Test(
        "A negative previous volume, which subtraction can make, follows the same formula.",
        arguments: [
            Row("-100", "100", -200), Row("-200", "-201", 1), Row("-200", "-199", -1), Row("-200", "-205", 3),
            Row("-200", "0", -100), Row("100", "-100", -200), Row("-100", "-100", 0), Row("100", "-50", -150),
            Row("200", "-1", -101), Row("200", "-3", -102)
        ]
    )
    func percentChange_negativeVolumes_followTheFormula(row: Row) {
        let change = Volume(gramReps: dec(row.current)).percentChange(from: Volume(gramReps: dec(row.previous)))
        #expect(change == row.percent)
    }

    @Test("A volume that is not a number has no percentage and does not trap.")
    func percentChange_notANumber_isNil() {
        let nan = Volume(gramReps: .nan)
        let real = Self.volume("24180", in: .lb)
        #expect(nan.percentChange(from: real) == nil)
        #expect(real.percentChange(from: nan) == nil)
        #expect(nan.percentChange(from: nan) == nil)
        #expect(nan.percentChange(from: .zero) == nil)
    }
}

/// Grams in one of `units`, built from integers as the brief's decision #9 defines the pound.
func gramsPerUnit(_ units: Units) -> Decimal {
    units == .lb ? gramsPerPound : 1000
}
