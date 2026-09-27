import Foundation
@testable import LedgerDomain
import Testing

@Suite("OneRepMax (adversarial)", .tags(.domain))
struct OneRepMaxAdversarialTests {
    static func estimate(_ weight: Weight, _ reps: Int) -> Weight? {
        OneRepMax.brzycki(weight: weight, reps: Reps(clamping: reps))
    }
}

extension OneRepMaxAdversarialTests {
    @Test("195 lb × 5 presents as 219 lb and 13 reps has no estimate (criterion 7, decision #4).")
    func brzycki_criterion7() throws {
        // 195 lb = 88,451 g; × 36 / 32 = 99,507.375 g = 219.376 lb → 219.
        let estimate = try #require(Self.estimate(pounds("195"), 5))
        #expect(estimate.grams == 99507)
        #expect(estimate.wholeValue(in: .lb) == 219)
        #expect(Self.estimate(pounds("195"), 13) == nil)
    }

    @Test("200 lb × 5 estimates 225 lb (criterion 12).")
    func brzycki_200x5_is225() throws {
        // 90,718 g × 1.125 = 102,057.75 → 102,058 g = .pounds(225).
        let estimate = try #require(Self.estimate(pounds("200"), 5))
        // ADR-007: exact 200 lb × 36 / 32 = 102,058.28325 g; the estimate rounds to the nearest gram.
        #expect(estimate == Weight(grams: 102_058))
        #expect(estimate.wholeValue(in: .lb) == 225)
    }

    @Test(
        "100 kg × r is 100,000 × 36 / (37 − r) g to the nearest gram for r = 1…12.",
        arguments: [
            (1, 100_000), (2, 102_857), (3, 105_882), (4, 109_091), (5, 112_500), (6, 116_129),
            (7, 120_000), (8, 124_138), (9, 128_571), (10, 133_333), (11, 138_462), (12, 144_000)
        ]
    )
    func brzycki_kiloTable(reps: Int, grams: Int) {
        #expect(Self.estimate(kilos("100"), reps)?.grams == Decimal(grams))
    }

    @Test(
        "Any rep count above 12 has no estimate, including absurd ones.",
        arguments: [13, 20, 36, 37, 38, 100, Int.max]
    )
    func brzycki_above12_isNil(reps: Int) {
        #expect(Self.estimate(pounds("135"), reps) == nil)
        #expect(OneRepMax.maximumReps == 12)
    }

    @Test("A single rep estimates exactly the weight lifted, and zero stays zero.")
    func brzycki_oneRepAndZero() {
        // ADR-007: the estimate is the weight rounded to the nearest gram (185 lb = 83,914.58845 g).
        #expect(Self.estimate(pounds("185"), 1) == Weight(grams: 83915))
        #expect(Self.estimate(pounds("185"), 1)?.wholeValue(in: .lb) == 185)
        #expect(Self.estimate(Weight(grams: 1), 1) == Weight(grams: 1))
        #expect(Self.estimate(.zero, 10) == .zero)
    }
}

@Suite("OneRepMax properties (adversarial)", .tags(.domain, .property))
struct OneRepMaxPropertyAdversarialTests {}

extension OneRepMaxPropertyAdversarialTests {
    @Test("brzycki is within half a gram of the exact Decimal formula for r ≤ 12.", arguments: PropertySeed.all)
    func brzycki_matchesExactFormula(seed: PropertySeed) throws {
        var generator = seed.generator
        let grams = Int.random(in: 0 ... 500_000, using: &generator)
        let reps = Int.random(in: 1 ... 12, using: &generator)
        let exact = Decimal(grams) * 36 / Decimal(37 - reps)
        let estimate = try #require(OneRepMaxAdversarialTests.estimate(Weight(grams: Decimal(grams)), reps))
        #expect(abs(estimate.grams - exact) <= dec("0.5"), "\(grams) g × \(reps)")
    }

    @Test(
        "More reps at the same weight never estimate lower, and the estimate is never below the weight.",
        arguments: PropertySeed.all
    )
    func brzycki_monotonicInReps(seed: PropertySeed) throws {
        var generator = seed.generator
        let weight = Weight(grams: Decimal(Int.random(in: 1 ... 500_000, using: &generator)))
        var previous = weight
        for reps in 1 ... 12 {
            let estimate = try #require(OneRepMaxAdversarialTests.estimate(weight, reps))
            #expect(estimate >= previous, "\(weight.grams) g × \(reps)")
            previous = estimate
        }
    }
}
