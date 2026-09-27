import Foundation
@testable import LedgerDomain
import Testing

/// A random rounding step with its unit and its value in that unit.
struct RandomStep {
    let step: Weight
    let units: Units
    let value: Decimal
}

/// Seeded invariants of `Weight` (brief test plan: round-trip, idempotent rounding; plus
/// lattice, monotonicity, symmetry and bound invariants the brief's definitions imply).
@Suite("Weight properties (adversarial)", .tags(.domain, .property))
struct WeightPropertyAdversarialTests {
    static let poundSteps = ["1.25", "2.5", "5", "10", "45"]
    static let kiloSteps = ["1.25", "2.5", "0.5", "1", "5", "20"]
    static let rules: [FloatingPointRoundingRule] = [
        .toNearestOrAwayFromZero, .toNearestOrEven, .up, .down, .towardZero, .awayFromZero
    ]

    /// A random step in either unit, with its unit and its value in that unit.
    static func randomStep(using generator: inout SeededGenerator) -> RandomStep {
        if Bool.random(using: &generator) {
            let text = poundSteps.randomElement(using: &generator) ?? "5"
            return RandomStep(step: pounds(text), units: .lb, value: dec(text))
        }
        let text = kiloSteps.randomElement(using: &generator) ?? "2.5"
        return RandomStep(step: kilos(text), units: .kg, value: dec(text))
    }

    static func randomRule(using generator: inout SeededGenerator) -> FloatingPointRoundingRule {
        rules.randomElement(using: &generator) ?? .toNearestOrAwayFromZero
    }
}

extension WeightPropertyAdversarialTests {
    @Test(
        "Every hundredth of a pound survives lb → g → lb (brief: identity at 0.5 lb resolution).",
        arguments: PropertySeed.all
    )
    func poundsRoundTrip_hundredths_isIdentity(seed: PropertySeed) {
        var generator = seed.generator
        let value = randomMultiple(of: dec("0.01"), in: -100_000 ... 500_000, using: &generator)
        // ADR-007: weights are exact, so lb → g → lb is the identity, not just to the hundredth.
        #expect(Weight.pounds(value).pounds == value)
        #expect(decimalRounded(Weight.pounds(value).pounds, scale: 2) == value)
        let halves = randomMultiple(of: dec("0.5"), in: 0 ... 2000, using: &generator)
        #expect(decimalRounded(Weight.pounds(halves).pounds * 2) / 2 == halves)
    }

    @Test("Every gram survives kg → g → kg exactly.", arguments: PropertySeed.all)
    func kilogramsRoundTrip_grams_isExact(seed: PropertySeed) {
        var generator = seed.generator
        let grams = Int.random(in: -1_000_000 ... 1_000_000, using: &generator)
        let weight = Weight.kilograms(Decimal(grams) / 1000)
        #expect(weight.grams == Decimal(grams))
        #expect(weight.kilograms == Decimal(grams) / 1000)
    }

    @Test("rounded(toStep:) is idempotent for every step and rule.", arguments: PropertySeed.all)
    func rounded_isIdempotent(seed: PropertySeed) {
        var generator = seed.generator
        let weight = Weight(grams: Decimal(Int.random(in: -300_000 ... 300_000, using: &generator)))
        let step = Self.randomStep(using: &generator).step
        let rule = Self.randomRule(using: &generator)
        let once = weight.rounded(toStep: step, rule)
        #expect(once.rounded(toStep: step, rule) == once, "\(weight.grams) g, step \(step.grams) g, \(rule)")
    }

    @Test("rounded(toStep:) lands exactly on n × step in the step's unit.", arguments: PropertySeed.all)
    func rounded_landsOnStepLattice(seed: PropertySeed) {
        var generator = seed.generator
        let weight = Weight(grams: Decimal(Int.random(in: 0 ... 300_000, using: &generator)))
        let random = Self.randomStep(using: &generator)
        let (step, units, stepValue) = (random.step, random.units, random.value)
        let result = weight.rounded(toStep: step, Self.randomRule(using: &generator))
        let count = decimalRounded(result.value(in: units) / stepValue)
        let lattice: Weight = units == .lb ? .pounds(count * stepValue) : .kilograms(count * stepValue)
        #expect(result == lattice, "\(weight.grams) g → \(result.grams) g, step \(stepValue) \(units)")
    }

    @Test("rounded(toStep:) is monotonic: a heavier input never rounds lighter.", arguments: PropertySeed.all)
    func rounded_isMonotonic(seed: PropertySeed) {
        var generator = seed.generator
        let lighter = Int.random(in: -200_000 ... 200_000, using: &generator)
        let heavier = lighter + Int.random(in: 0 ... 5000, using: &generator)
        let step = Self.randomStep(using: &generator).step
        let rule = Self.randomRule(using: &generator)
        let low = Weight(grams: Decimal(lighter)).rounded(toStep: step, rule)
        let high = Weight(grams: Decimal(heavier)).rounded(toStep: step, rule)
        #expect(low <= high, "\(lighter) g vs \(heavier) g, step \(step.grams) g, \(rule)")
    }

    @Test("Symmetric rules commute with negation; .up and .down mirror each other.", arguments: PropertySeed.all)
    func rounded_negation_isSymmetric(seed: PropertySeed) {
        var generator = seed.generator
        let grams = Int.random(in: 1 ... 300_000, using: &generator)
        let step = Self.randomStep(using: &generator).step
        let positive = Weight(grams: Decimal(grams))
        let negative = Weight(grams: Decimal(-grams))
        for rule in [FloatingPointRoundingRule.toNearestOrAwayFromZero, .toNearestOrEven, .towardZero, .awayFromZero] {
            #expect(
                negative.rounded(toStep: step, rule).grams == -positive.rounded(toStep: step, rule).grams,
                "\(rule)"
            )
        }
        #expect(negative.rounded(toStep: step, .up).grams == -positive.rounded(toStep: step, .down).grams)
        #expect(negative.rounded(toStep: step, .down).grams == -positive.rounded(toStep: step, .up).grams)
    }

    @Test("Nearest rounding moves at most half a step; directed rules move the right way.", arguments: PropertySeed.all)
    func rounded_respectsBounds(seed: PropertySeed) {
        var generator = seed.generator
        let weight = Weight(grams: Decimal(Int.random(in: -300_000 ... 300_000, using: &generator)))
        let step = Self.randomStep(using: &generator).step
        // ADR-007: rounding is exact, so no slack (was 6 g for the old 0.01 lb quantum).
        let slack: Decimal = 0
        let nearest = weight.rounded(toStep: step)
        #expect(abs(nearest.grams - weight.grams) * 2 <= step.grams + 2 * slack)
        #expect(weight.rounded(toStep: step, .up).grams >= weight.grams - slack)
        #expect(weight.rounded(toStep: step, .down).grams <= weight.grams + slack)
        #expect(abs(weight.rounded(toStep: step, .towardZero).grams) <= abs(weight.grams) + slack)
        #expect(abs(weight.rounded(toStep: step, .awayFromZero).grams) >= abs(weight.grams) - slack)
    }

    @Test(
        "Quarter-unit weights format exactly as their decimal text, never with trailing zeros.",
        arguments: PropertySeed.all
    )
    func formatted_quarterValues_printExactly(seed: PropertySeed) {
        var generator = seed.generator
        let value = randomMultiple(of: dec("0.25"), in: 0 ... 4000, using: &generator)
        #expect(Weight.pounds(value).formatted(in: .lb) == "\(value)")
        #expect(Weight.kilograms(value).formatted(in: .kg) == "\(value)")
    }

    @Test("Any weight formats to at most two decimals and reads back within 0.05 units.", arguments: PropertySeed.all)
    func formatted_anyWeight_isCloseAndShort(seed: PropertySeed) throws {
        var generator = seed.generator
        let weight = Weight(grams: Decimal(Int.random(in: 0 ... 500_000, using: &generator)))
        for units in Units.allCases {
            let text = weight.formatted(in: units)
            let parsed = try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), "\(text)")
            #expect(abs(parsed - weight.value(in: units)) <= dec("0.05"), "\(weight.grams) g → \(text) \(units)")
            #expect((text.split(separator: ".").dropFirst().first?.count ?? 0) <= 2, "\(text)")
            #expect(!text.contains(","), "\(text)")
        }
    }

    @Test("advanced(bySteps:of:) equals the pound literal start + n × step.", arguments: PropertySeed.all)
    func advancedBySteps_matchesPoundLiteral(seed: PropertySeed) {
        var generator = seed.generator
        let start = randomMultiple(of: dec("2.5"), in: 0 ... 200, using: &generator)
        let stepText = ["1.25", "2.5", "5"].randomElement(using: &generator) ?? "5"
        let count = Int.random(in: 0 ... 200, using: &generator)
        let expected = Weight.pounds(start + Decimal(count) * dec(stepText))
        #expect(Weight.pounds(start).advanced(bySteps: count, of: pounds(stepText)) == expected)
    }

    @Test("Ordering and equality agree with grams.", arguments: PropertySeed.all)
    func comparable_agreesWithGrams(seed: PropertySeed) {
        var generator = seed.generator
        let left = Int.random(in: -1000 ... 1000, using: &generator)
        let right = Int.random(in: -1000 ... 1000, using: &generator)
        #expect((Weight(grams: Decimal(left)) < Weight(grams: Decimal(right))) == (left < right))
        #expect((Weight(grams: Decimal(left)) + Weight(grams: Decimal(right))).grams == Decimal(left + right))
    }
}
