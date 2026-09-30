import Foundation
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S1 adversarial round 1: the `_e7g` columns (ADR-007) against every weight F02 makes, the
/// `Int64` edges, and an integer oracle, independent of `Decimal`, for which values are storable.
@Suite("Adversarial S1 · exact weight columns", .tags(.persistence))
struct ExactWeightColumnAdversarialTests {
    /// 0.01 lb in stored units (10⁻⁷ g): 4.5359237 g.
    static let hundredthPound: Int64 = 45_359_237
    /// 1 g in stored units.
    static let gram: Int64 = 10_000_000

    @Test("Every hundredth of a pound from −100 to 1,500 lb is h × 45,359,237 units and reads back equal")
    func everyHundredthPound_isStoredExactly() throws {
        for hundredths in Int64(-10000) ... 150_000 {
            let weight = Weight.pounds(Decimal(sign: .plus, exponent: -2, significand: Decimal(hundredths)))
            let stored = try weight.e7g()
            guard stored == hundredths * Self.hundredthPound, Weight(e7g: stored) == weight else {
                Issue.record("\(hundredths) hundredths of a pound stored as \(stored)")
                return
            }
        }
    }

    @Test("Every 10 g from 0 to 500 kg, and every gram to 50 kg, is stored exactly and reads back equal")
    func kilogramGrid_isStoredExactly() throws {
        let grid = Array(stride(from: Int64(0), through: 500_000, by: 10)) + Array(Int64(1) ... 50000)
        for grams in grid {
            let weight = Weight.kilograms(Decimal(sign: .plus, exponent: -3, significand: Decimal(grams)))
            let stored = try weight.e7g()
            guard stored == grams * Self.gram, Weight(e7g: stored) == weight else {
                Issue.record("\(grams) g stored as \(stored)")
                return
            }
        }
    }

    @Test("Deload and drop loads (× 0.85 rounded to a step) and every Brzycki e1RM are storable and exact")
    func ruleOutputs_areStorable() throws {
        let factor = Decimal(sign: .plus, exponent: -2, significand: 85)
        let pounds = stride(from: 4500, through: 70000, by: 125).map { Weight.pounds(Self.hundredths($0)) }
        let kilograms = stride(from: 2000, through: 32000, by: 50).map { Weight.kilograms(Self.hundredths($0)) }
        let steps = [125, 250, 500, 1000].map { Weight.pounds(Self.hundredths($0)) }
            + [50, 125, 250].map { Weight.kilograms(Self.hundredths($0)) }
        for load in pounds + kilograms {
            for step in steps {
                let deload = load.scaled(by: factor).rounded(toStep: step)
                #expect(try Weight(e7g: deload.e7g()) == deload, "\(load.grams) g on \(step.grams) g")
            }
            for reps in 1 ... OneRepMax.maximumReps {
                let estimate = try #require(OneRepMax.brzycki(weight: load, reps: Reps(clamping: reps)))
                let stored = try estimate.e7g()
                #expect(stored % Self.gram == 0 && Weight(e7g: stored) == estimate, "\(load.grams) g × \(reps)")
                let volume = Volume(weight: load, reps: Reps(clamping: reps))
                #expect(try Volume(e7gReps: volume.e7gReps()) == volume)
            }
        }
    }

    @Test("The smallest and largest storable values round-trip, and one unit beyond either edge is refused")
    func edges_roundTrip_andOneBeyondIsRefused() throws {
        let unit = Weight(grams: Decimal(sign: .plus, exponent: -7, significand: 1))
        for count in [Int64.min, .min + 1, -1, 0, 1, .max - 1, .max] {
            #expect(try Weight(e7g: count).e7g() == count)
            #expect(try Volume(e7gReps: count).e7gReps() == count)
        }
        #expect(try unit.e7g() == 1)
        let belowMin = Weight(e7g: .min) - unit
        let aboveMax = Weight(e7g: .max) + unit
        #expect(throws: LedgerPersistenceError.inexactWeight(belowMin.grams)) { try belowMin.e7g() }
        #expect(throws: LedgerPersistenceError.inexactWeight(aboveMax.grams)) { try aboveMax.e7g() }
        // The heaviest whole hundredth of a pound that fits, and the next one.
        let heaviest = Int64.max / Self.hundredthPound
        let fits = Weight.pounds(Decimal(sign: .plus, exponent: -2, significand: Decimal(heaviest)))
        #expect(try fits.e7g() == heaviest * Self.hundredthPound)
        let next = Weight.pounds(Decimal(sign: .plus, exponent: -2, significand: Decimal(heaviest + 1)))
        #expect(throws: LedgerPersistenceError.inexactWeight(next.grams)) { try next.e7g() }
        #expect(throws: LedgerPersistenceError.inexactWeight(next.grams.negated())) { try (Weight.zero - next).e7g() }
    }

    @Test("Values that are not whole units are refused with the value itself: no rounding, either sign")
    func nonRepresentable_isRefusedUnrounded() {
        let third = Decimal(1) / Decimal(3) // 0.333… g to 38 digits
        let cases: [Decimal] = [
            Weight.pounds(Decimal(1) / 8).grams, // 56.69904625 g
            Weight.pounds(Decimal(sign: .plus, exponent: -3, significand: 1)).grams, // 0.001 lb
            Weight.pounds(Decimal(sign: .plus, exponent: -2, significand: 1) / 2).grams, // half a hundredth
            third, third.negated(),
            Decimal(sign: .plus, exponent: -8, significand: 5), Decimal(sign: .minus, exponent: -8, significand: 5),
            Decimal(sign: .plus, exponent: -38, significand: 1)
        ]
        for grams in cases {
            #expect(throws: LedgerPersistenceError.inexactWeight(grams), "\(grams)") {
                try Weight(grams: grams).e7g()
            }
            #expect(throws: LedgerPersistenceError.inexactWeight(grams), "\(grams)") {
                try Volume(gramReps: grams).e7gReps()
            }
        }
    }

    @Test(
        "A decimal is stored iff an integer oracle says it is a whole count of units in Int64, and then exactly",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func e7g_agreesWithAnIntegerOracle(_ seed: PropertySeed) throws {
        var random = seed.generator
        for _ in 0 ..< 50 {
            var significand = Int64.random(in: .min ... .max, using: &random) >> Int.random(
                in: 0 ... 62,
                using: &random
            )
            for _ in 0 ..< Int.random(in: 0 ... 4, using: &random) { // trailing zeros that Decimal normalises
                let (product, overflow) = significand.multipliedReportingOverflow(by: 10)
                significand = overflow ? significand : product
            }
            let exponent = Int.random(in: -30 ... 14, using: &random)
            let grams = Decimal(sign: .plus, exponent: exponent, significand: Decimal(significand))
            if let expected = Self.oracle(significand, shift: exponent + 7) {
                #expect(try Weight(grams: grams).e7g() == expected, "\(significand)e\(exponent)")
                #expect(Weight(e7g: expected) == Weight(grams: grams))
            } else {
                #expect(throws: LedgerPersistenceError.inexactWeight(grams), "\(significand)e\(exponent)") {
                    try Weight(grams: grams).e7g()
                }
            }
        }
    }

    /// `count` hundredths, exactly.
    static func hundredths(_ count: Int) -> Decimal {
        Decimal(sign: .plus, exponent: -2, significand: Decimal(count))
    }

    /// `significand × 10^shift` when it is an integer that fits `Int64`, by integer arithmetic only.
    static func oracle(_ significand: Int64, shift: Int) -> Int64? {
        guard significand != 0 else {
            return 0
        }
        var value = significand
        if shift >= 0 {
            for _ in 0 ..< shift {
                let (product, overflow) = value.multipliedReportingOverflow(by: 10)
                guard !overflow else {
                    return nil
                }
                value = product
            }
            return value
        }
        for _ in 0 ..< -shift {
            guard value % 10 == 0 else {
                return nil
            }
            value /= 10
        }
        return value
    }
}

private extension Decimal {
    func negated() -> Decimal {
        Decimal(0) - self
    }
}
