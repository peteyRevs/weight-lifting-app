import Foundation
@testable import LedgerDomain
import Testing

/// One `rounded(toStep:_:)` row: expected values follow Swift's `FloatingPointRoundingRule`
/// semantics applied to `value / step` in the step's unit (brief: "nearest multiple of step").
struct RoundingCase: Sendable, CustomStringConvertible {
    let value: Weight
    let step: Weight
    let rule: FloatingPointRoundingRule
    let expected: Weight
    let label: String

    var description: String {
        "\(label) \(rule)"
    }

    static func lbRows(_ value: String, step: String, _ expectations: [(FloatingPointRoundingRule, String)]) -> [Self] {
        expectations.map {
            Self(
                value: pounds(value),
                step: pounds(step),
                rule: $0.0,
                expected: pounds($0.1),
                label: "\(value) lb / \(step) lb"
            )
        }
    }

    static func kgRows(_ value: String, step: String, _ expectations: [(FloatingPointRoundingRule, String)]) -> [Self] {
        expectations.map {
            Self(
                value: kilos(value),
                step: kilos(step),
                rule: $0.0,
                expected: kilos($0.1),
                label: "\(value) kg / \(step) kg"
            )
        }
    }

    static let all: [Self] = lbRows("242.5", step: "5", [
        (.toNearestOrAwayFromZero, "245"), (.toNearestOrEven, "240"), (.up, "245"),
        (.down, "240"), (.towardZero, "240"), (.awayFromZero, "245")
    ]) + lbRows("247.5", step: "5", [(.toNearestOrEven, "250"), (.toNearestOrAwayFromZero, "250")])
        + lbRows("243", step: "5", [
            (.toNearestOrAwayFromZero, "245"), (.toNearestOrEven, "245"), (.up, "245"),
            (.down, "240"), (.towardZero, "240"), (.awayFromZero, "245")
        ]) + lbRows("241", step: "5", [
            (.toNearestOrAwayFromZero, "240"), (.toNearestOrEven, "240"), (.up, "245"),
            (.down, "240"), (.towardZero, "240"), (.awayFromZero, "245")
        ]) + lbRows("-242.5", step: "5", [
            (.toNearestOrAwayFromZero, "-245"), (.toNearestOrEven, "-240"), (.up, "-240"),
            (.down, "-245"), (.towardZero, "-240"), (.awayFromZero, "-245")
        ]) + lbRows("-241", step: "5", [
            (.toNearestOrAwayFromZero, "-240"), (.toNearestOrEven, "-240"), (.up, "-240"),
            (.down, "-245"), (.towardZero, "-240"), (.awayFromZero, "-245")
        ]) + lbRows("2.5", step: "5", [(.toNearestOrAwayFromZero, "5"), (.toNearestOrEven, "0")])
        + lbRows("101", step: "1.25", [(.toNearestOrAwayFromZero, "101.25"), (.down, "100"), (.up, "101.25")])
        + lbRows("51.25", step: "2.5", [(.toNearestOrAwayFromZero, "52.5"), (.toNearestOrEven, "50")])
        + lbRows("185", step: "5", [(.up, "185"), (.down, "185"), (.awayFromZero, "185"), (.towardZero, "185")])
        + lbRows("0", step: "2.5", [(.up, "0"), (.down, "0"), (.awayFromZero, "0")])
        + kgRows("51.25", step: "2.5", [
            (.toNearestOrAwayFromZero, "52.5"), (.toNearestOrEven, "50"), (.up, "52.5"),
            (.down, "50"), (.towardZero, "50"), (.awayFromZero, "52.5")
        ]) + kgRows("52.6", step: "1.25", [(.toNearestOrAwayFromZero, "52.5"), (.up, "53.75"), (.down, "52.5")])
        + kgRows("-51.25", step: "2.5", [(.up, "-50"), (.down, "-52.5"), (.toNearestOrEven, "-50")])
        + kgRows("52.5", step: "2.5", [(.up, "52.5"), (.down, "52.5"), (.toNearestOrEven, "52.5")])
        + kgRows("33", step: "11", [(.toNearestOrAwayFromZero, "33"), (.up, "33"), (.down, "33")])
        + kgRows("24", step: "4", [(.toNearestOrAwayFromZero, "24"), (.up, "24"), (.down, "24")])
}

@Suite("Weight (adversarial)", .tags(.domain))
struct WeightAdversarialTests {}

extension WeightAdversarialTests {
    @Test("185 lb is exactly 83,914.58845 g and formats as 185 lb and 83.9 kg (criterion 1, ADR-007).")
    func pounds185_convertsAndFormats_matchesCriterion1() {
        let weight = pounds("185")
        #expect(weight.grams == dec("83914.58845"))
        #expect(weight.formatted(in: .lb) == "185")
        #expect(weight.formatted(in: .kg) == "83.9")
    }

    @Test(
        "Pound inputs convert to exact grams with no rounding (ADR-007).",
        arguments: [
            ("0", "0"), ("1", "453.59237"), ("2.5", "1133.980925"), ("5", "2267.96185"), ("45", "20411.65665"),
            ("242.5", "109996.149725"), ("-185", "-83914.58845"), ("0.001", "0.45359237"), ("-0.001", "-0.45359237")
        ]
    )
    func pounds_nearestGram_table(text: String, grams: String) {
        // 1 lb = 453.59237 g exactly; e.g. 242.5 × 453.59237 = 109,996.149725 g, kept exactly.
        #expect(pounds(text).grams == dec(grams))
    }

    @Test(
        "Kilogram inputs convert to exact grams, sub-gram values included (ADR-007).",
        arguments: [
            ("20", "20000"), ("83.915", "83915"), ("0.0025", "2.5"), ("-0.0025", "-2.5"), ("0.0015", "1.5"),
            ("0.0005", "0.5")
        ]
    )
    func kilograms_nearestGram_tiesAwayFromZero(text: String, grams: String) {
        #expect(kilos(text).grams == dec(grams))
    }

    @Test("242.25 lb rounds down to 240 lb and the 242.5 lb tie rounds away to 245 lb (criterion 2).")
    func roundedToStep_criterion2_tieAwayFromZero() {
        #expect(pounds("242.25").rounded(toStep: pounds("5")) == pounds("240"))
        #expect(pounds("242.5").rounded(toStep: pounds("5")) == pounds("245"))
    }

    @Test("rounded(toStep:) honours every FloatingPointRoundingRule in both units.", arguments: RoundingCase.all)
    func roundedToStep_everyRule_matchesSwiftSemantics(row: RoundingCase) {
        #expect(row.value.rounded(toStep: row.step, row.rule) == row.expected)
    }

    @Test("A pound weight rounded to a kilogram step (and back) lands on that unit's lattice.")
    func roundedToStep_crossUnit_landsOnStepUnit() {
        // 185 lb = 83.915 kg; / 2.5 = 33.566 → 34 × 2.5 = 85 kg (nearest), 82.5 kg (down).
        #expect(pounds("185").rounded(toStep: kilos("2.5")) == kilos("85"))
        #expect(pounds("185").rounded(toStep: kilos("2.5"), .down) == kilos("82.5"))
        // 100 kg = 220.462 lb; / 5 = 44.09 → 220 lb (nearest), 225 lb (up).
        #expect(kilos("100").rounded(toStep: pounds("5")) == pounds("220"))
        #expect(kilos("100").rounded(toStep: pounds("5"), .up) == pounds("225"))
    }

    @Test("A zero or negative step leaves the weight unchanged (documented contract).")
    func roundedToStep_nonPositiveStep_returnsSelf() {
        #expect(pounds("187.3").rounded(toStep: .zero) == pounds("187.3"))
        #expect(pounds("187.3").rounded(toStep: pounds("-5")) == pounds("187.3"))
    }

    @Test("Adding steps with advanced(bySteps:of:) never drifts off the pound lattice.")
    func advancedBySteps_poundSteps_equalsPoundsLiteral() {
        #expect(pounds("185").advanced(bySteps: 6, of: pounds("2.5")) == pounds("200"))
        #expect(pounds("250").advanced(bySteps: 7, of: pounds("5")) == pounds("285"))
        #expect(pounds("0").advanced(bySteps: 100, of: pounds("2.5")) == pounds("250"))
        #expect(kilos("80").advanced(bySteps: 3, of: kilos("2.5")).grams == 87500)
        #expect(pounds("185").advanced(bySteps: 0, of: pounds("5")) == pounds("185"))
        #expect(pounds("185").advanced(bySteps: -2, of: pounds("5")) == pounds("175"))
    }

    @Test("scaled(by:) is the exact Decimal product (ADR-007: only rounded(toStep:) rounds).")
    func scaled_exactDecimal_nearestGram() {
        // 123,456,789 g × 0.85 = 104,938,270.65 g exactly.
        #expect(Weight(grams: 123_456_789).scaled(by: dec("0.85")).grams == dec("104938270.65"))
        #expect(pounds("185").scaled(by: 1) == pounds("185"))
        #expect(pounds("185").scaled(by: 0) == .zero)
        #expect(Weight(grams: 1000).scaled(by: dec("0.5")).grams == 500)
        #expect(Weight(grams: 1000).scaled(by: -1).grams == -1000)
        // 285 lb (129,273.82545 g) × 0.85 = 109,882.7516325 g = exactly 242.25 lb.
        #expect(pounds("285").scaled(by: dec("0.85")).grams == dec("109882.7516325"))
        #expect(pounds("285").scaled(by: dec("0.85")) == pounds("242.25"))
    }
}

extension WeightAdversarialTests {
    @Test(
        "formatted(in:) prints exact values without trailing zeros and converted values to one decimal.",
        arguments: [
            (Weight.zero, Units.lb, "0"), (.zero, .kg, "0"), (pounds("52.5"), .lb, "52.5"),
            (pounds("46.25"), .lb, "46.25"), (kilos("1.25"), .kg, "1.25"), (kilos("102.5"), .kg, "102.5"),
            (kilos("20"), .lb, "44.1"), (kilos("100"), .lb, "220.5"), (pounds("45"), .kg, "20.4"),
            (pounds("100"), .kg, "45.4"), (kilos("83.9"), .kg, "83.9"), (pounds("600"), .lb, "600")
        ]
    )
    func formatted_table(weight: Weight, units: Units, text: String) {
        // Converted values: 20 kg = 44.092 lb, 100 kg = 220.462 lb, 45 lb = 20.412 kg, 100 lb = 45.359 kg.
        #expect(weight.formatted(in: units) == text)
    }

    @Test("value(in:) is the exact pounds/kilograms value and kilograms are exact to the gram.")
    func valueIn_matchesUnitProperties() {
        let weight = kilos("83.915")
        #expect(weight.kilograms == dec("83.915"))
        #expect(weight.value(in: .kg) == weight.kilograms)
        #expect(weight.value(in: .lb) == weight.pounds)
        #expect(Weight(grams: 453).pounds < 1)
        #expect(Weight(grams: 454).pounds > 1)
    }

    @Test("Arithmetic and ordering work in grams across units.")
    func arithmetic_andOrdering_inGrams() {
        #expect(pounds("180") + pounds("5") == pounds("185"))
        #expect(pounds("185") - pounds("185") == .zero)
        #expect(pounds("185") + .zero == pounds("185"))
        #expect(kilos("20") < pounds("45"))
        #expect(pounds("45") > kilos("20"))
        #expect([pounds("45"), kilos("20"), .zero, pounds("-5")].sorted() == [
            pounds("-5"),
            .zero,
            kilos("20"),
            pounds("45")
        ])
        #expect(pounds("185") == Weight(grams: dec("83914.58845")))
    }

    @Test(
        "Weight survives a Codable round-trip at the extremes.",
        arguments: [0, 1, -1, 83915, Int.max, Int.min + 1]
    )
    func codable_roundTrip_extremes(grams: Int) throws {
        #expect(try Adversarial.roundTrip(Weight(grams: Decimal(grams))) == Weight(grams: Decimal(grams)))
    }
}
