import Foundation
@testable import LedgerDomain
import Testing

@Suite("OneRepMax", .tags(.domain))
struct OneRepMaxTests {
    @Test("Brzycki is w × 36 / (37 − r) to the nearest gram (decision #4)", arguments: 1 ... 12)
    func brzycki_matchesFormula_forReps1Through12(reps: Int) throws {
        // 200 lb = 90,718.474 g exactly; the estimate is w × 36 / (37 − r) rounded to the nearest gram.
        let weight = Weight.pounds(200)
        let exact = weight.grams * 36 / Decimal(37 - reps)
        let estimate = try #require(try OneRepMax.brzycki(weight: weight, reps: Fixtures.reps(reps)))
        #expect(estimate.grams == estimate.grams.rounded(scale: 0, .toNearestOrAwayFromZero))
        #expect(abs(estimate.grams - exact) <= dec("0.5"))
    }

    @Test("195 lb × 5 presents as 219 lb, not the prototype's 218 (criterion 7)")
    func brzycki_195x5_is219lb() throws {
        let estimate = try #require(try OneRepMax.brzycki(weight: .pounds(195), reps: Fixtures.reps(5)))
        // 195 lb = 88,450.51215 g; × 36 / 32 = 99,506.826… → 99,507 g (219.375 lb) → 219.
        #expect(estimate.grams == 99507)
        #expect(estimate.wholeValue(in: .lb) == 219)
        #expect(estimate.pounds.rounded(scale: 2, .toNearestOrAwayFromZero) == dec("219.38"))
    }

    @Test("Above 12 reps there is no estimate (decision #4, criterion 7)", arguments: [13, 20, 36, 37, 50])
    func brzycki_returnsNil_above12Reps(reps: Int) throws {
        #expect(try OneRepMax.brzycki(weight: .pounds(135), reps: Fixtures.reps(reps)) == nil)
    }

    @Test("One rep estimates the weight itself, to the nearest gram (ADR-007)")
    func brzycki_oneRep_returnsWeight() throws {
        // 315 lb = 142,881.59655 g → 142,882 g.
        #expect(try OneRepMax.brzycki(weight: .pounds(315), reps: Fixtures.reps(1)) == Weight(grams: 142_882))
        #expect(try OneRepMax.brzycki(weight: .kilograms(140), reps: Fixtures.reps(1)) == .kilograms(140))
        #expect(OneRepMax.brzycki(weight: .zero, reps: .one) == .zero)
    }

    @Test("A heavier weight never estimates lower at the same reps", .tags(.property), arguments: PropertySeed.all)
    func brzycki_isMonotonicInWeight(seed: PropertySeed) throws {
        var generator = seed.generator
        let reps = try Fixtures.reps(Int.random(in: 1 ... 12, using: &generator))
        let lighter = Weight(grams: Decimal(Int.random(in: 0 ... 300_000, using: &generator)))
        let heavier = lighter + Weight(grams: Decimal(Int.random(in: 0 ... 5000, using: &generator)))
        let low = try #require(OneRepMax.brzycki(weight: lighter, reps: reps))
        let high = try #require(OneRepMax.brzycki(weight: heavier, reps: reps))
        #expect(low <= high)
        #expect(low.grams >= lighter.grams.rounded(scale: 0, .toNearestOrAwayFromZero))
    }
}
