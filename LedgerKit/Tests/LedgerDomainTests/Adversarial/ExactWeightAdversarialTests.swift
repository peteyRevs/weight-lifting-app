import Foundation
@testable import LedgerDomain
import Testing

/// ADR-007 round 2: `Weight` is an exact Decimal mass. Expected values are exact decimal products
/// of 453.59237 g/lb; nothing rounds except `rounded(toStep:)` and the Brzycki estimate.
@Suite("Exact weight (adversarial, ADR-007)", .tags(.domain))
struct ExactWeightAdversarialTests {
    /// `count` additions of `step` to `start` with plain `+`.
    static func stepped(_ start: Weight, _ step: Weight, _ count: Int) -> Weight {
        (0 ..< count).reduce(start) { total, _ in total + step }
    }
}

extension ExactWeightAdversarialTests {
    @Test("185 lb + 6 × 2.5 lb with plain + is exactly 200 lb (round-1 spec question 2).")
    func plus_stepperDrift_isGone() {
        #expect(Self.stepped(pounds("185"), pounds("2.5"), 6) == pounds("200"))
        #expect(Self.stepped(.zero, pounds("2.5"), 100) == pounds("250"))
        #expect(Self.stepped(.zero, pounds("0.01"), 1000) == pounds("10"))
        #expect(Self.stepped(kilos("20"), kilos("1.25"), 64) == kilos("100"))
        #expect(Self.stepped(pounds("200"), pounds("-2.5"), 80) == .zero)
    }

    @Test("A stepper-built 200 lb ties a stored 200 lb best, so it is not a weight PR (decision #3).")
    func plus_stepperLoad_doesNotFakeAPR() throws {
        let stepped = Self.stepped(pounds("185"), pounds("2.5"), 6)
        let workout = try Fixtures.workout([Adversarial.exercise(rows: [Adversarial.row(1, weight: stepped, reps: 5)])])
        let records = try PersonalRecords.detect(
            workout: workout,
            bestE1RM: [Fixtures.bench.id: pounds("1000")],
            bestWeightAtReps: [Fixtures.bench.id: [Fixtures.reps(5): pounds("200")]],
            now: Fixtures.now
        )
        #expect(records.isEmpty)
    }

    @Test("Mixed-unit arithmetic is exact and reversible.")
    func mixedUnits_areExact() {
        #expect(kilos("20") + pounds("45") - pounds("45") == kilos("20"))
        #expect(pounds("1").kilograms == dec("0.45359237"))
        #expect(kilos("0.45359237") == pounds("1"))
        #expect(kilos("0.45359237").pounds == 1)
        #expect(pounds("45") - kilos("20") == Weight(grams: dec("411.65665")))
        #expect(pounds("5") - pounds("2.5") == pounds("2.5"))
    }

    @Test(
        "lb → g → lb and kg → g → kg are the identity, however many decimals (ADR-007).",
        arguments: ["185", "242.5", "0.01", "0.0001", "123456.789", "-46.25", "0.125", "99999.99999"]
    )
    func unitRoundTrip_isIdentity(text: String) {
        #expect(pounds(text).pounds == dec(text))
        #expect(kilos(text).kilograms == dec(text))
        #expect(pounds(text).value(in: .lb) == dec(text))
    }

    @Test("Equal masses from different construction paths are equal, order equally and hash equally.")
    func constructionPaths_areNumericallyIdentical() {
        let paths = [
            pounds("2.5"), Weight.pounds(2.5), Weight(grams: dec("1133.980925")), kilos("1.133980925"),
            Weight(grams: dec("1133.9809250")), pounds("5") - pounds("2.5"), pounds("1.25").scaled(by: 2),
            pounds("2.50000")
        ]
        #expect(Set(paths).count == 1)
        #expect(Set(paths.map(\.hashValue)).count == 1)
        for path in paths {
            #expect(path == paths[0])
            #expect(!(path < paths[0]) && !(paths[0] < path))
        }
    }

    @Test("1.0 g, 1.00 g and 1 g are one value; zero has one hash however it is reached (ADR-007).")
    func trailingZerosAndZero_areOneValue() {
        let ones = [
            Weight(grams: 1),
            Weight(grams: dec("1.0")),
            Weight(grams: dec("1.00")),
            Weight(grams: dec("0.10") * 10)
        ]
        #expect(Set(ones).count == 1)
        let zeros = [
            Weight.zero, Weight(grams: dec("0.000")), pounds("0"), Weight.zero.scaled(by: -1),
            pounds("5") - pounds("5"),
            pounds("-2.5") + pounds("2.5")
        ]
        #expect(Set(zeros).count == 1)
        #expect(zeros.allSatisfy { $0 == .zero && !($0 < .zero) })
        #expect(Set([PRKind.weightAtReps(ones[0], .one), .weightAtReps(ones[2], .one)]).count == 1)
    }

    @Test("A negative near-zero difference never formats as '-0'.")
    func formatted_negativeNearZero_isZero() {
        // 185 lb − 83.915 kg = −0.41155 g: −0.0009 lb and −0.0004 kg, both 0 at display precision.
        let difference = pounds("185") - kilos("83.915")
        #expect(difference < .zero)
        #expect(difference.formatted(in: .lb) == "0")
        #expect(difference.formatted(in: .kg) == "0")
        #expect(Weight.zero.scaled(by: -1).formatted(in: .lb) == "0")
        #expect(Weight(grams: dec("-0.0000001")).formatted(in: .kg) == "0")
    }

    @Test("Tiny and huge exact masses keep every digit and order correctly.")
    func extremes_keepPrecision() {
        let unit = Weight(grams: dec("0.0000001"))
        #expect(unit > .zero)
        #expect(unit + unit == Weight(grams: dec("0.0000002")))
        #expect(Self.stepped(.zero, unit, 10_000_000 / 100_000) == Weight(grams: dec("0.00001")))
        let huge = pounds("12345678901234567890.123456789")
        #expect(huge.pounds == dec("12345678901234567890.123456789"))
        #expect(huge + unit > huge)
        #expect(huge - huge == .zero)
        #expect(Weight(grams: dec("1e30")).kilograms == dec("1e27"))
    }

    @Test(
        "Exact half-step ties now round by the rule, on any step (ADR-007: ties are real ties).",
        arguments: [
            (FloatingPointRoundingRule.toNearestOrAwayFromZero, "181.25", "-181.25"),
            (.toNearestOrEven, "180", "-180"), (.up, "181.25", "-180"), (.down, "180", "-181.25"),
            (.towardZero, "180", "-180"), (.awayFromZero, "181.25", "-181.25")
        ]
    )
    func rounded_exactQuarterPoundTie_followsRule(rule: FloatingPointRoundingRule, positive: String, negative: String) {
        // ±180.625 lb = ±144.5 × 1.25 lb exactly.
        #expect(pounds("180.625").rounded(toStep: pounds("1.25"), rule) == pounds(positive))
        #expect(pounds("-180.625").rounded(toStep: pounds("1.25"), rule) == pounds(negative))
    }

    @Test("A kilogram value that is exactly half a pound step is a tie in pounds.")
    func rounded_crossUnitExactTie() {
        // 1.133980925 kg = 2.5 lb = 0.5 × 5 lb.
        #expect(kilos("1.133980925").rounded(toStep: pounds("5")) == pounds("5"))
        #expect(kilos("1.133980925").rounded(toStep: pounds("5"), .toNearestOrEven) == .zero)
        // 0.25 kg on a 0.5 kg step, and 33 kg on 11 kg (round-1 bug A) stay exact.
        #expect(kilos("0.25").rounded(toStep: kilos("0.5")) == kilos("0.5"))
        #expect(kilos("33").rounded(toStep: kilos("11")) == kilos("33"))
        #expect(kilos("64.75").rounded(toStep: kilos("64.75"), .down) == kilos("64.75"))
    }

    @Test("Volume over thousands of reps is exact (round-1 spec question 3).")
    func volume_longHorizon_isExact() throws {
        let set = try Volume(weight: pounds("185"), reps: Fixtures.reps(5))
        let month = (0 ..< 200).reduce(Volume.zero) { total, _ in total + set }
        #expect(month.formatted(in: .lb) == "185,000")
        let decade = (0 ..< 10000).reduce(Volume.zero) { total, _ in total + set }
        #expect(decade.formatted(in: .lb) == "9,250,000")
        #expect(decade == Volume(gramReps: pounds("9250000").grams))
        #expect(decade - decade == .zero)
    }
}
