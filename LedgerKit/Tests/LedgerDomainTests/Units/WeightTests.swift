import Foundation
@testable import LedgerDomain
import Testing

@Suite("Weight", .tags(.domain))
struct WeightTests {
    @Test("Pounds and kilograms convert to the nearest gram exactly (criterion 1)")
    func pounds_toGrams_exact() {
        #expect(Weight.pounds(185).grams == 83915)
        #expect(Weight.pounds(1).grams == 454)
        #expect(Weight.pounds(2.5).grams == 1134)
        #expect(Weight.pounds(dec("453.59237")).grams == 205_746)
        #expect(Weight.kilograms(dec("83.915")).grams == 83915)
        #expect(Weight.kilograms(1.25).grams == 1250)
        #expect(Weight.pounds(185).formatted(in: .lb) == "185")
        #expect(Weight.pounds(185).formatted(in: .kg) == "83.9")
    }

    @Test("Values read back exactly in either unit")
    func value_inUnits_isExact() {
        #expect(Weight(grams: 1000).kilograms == 1)
        #expect(Weight(grams: 453_592).value(in: .kg) == dec("453.592"))
        #expect(Weight.pounds(5).pounds.rounded(scale: 4, .toNearestOrAwayFromZero) == dec("5.0001"))
        #expect(Weight(grams: 45_359_237).pounds == 100_000)
    }

    @Test("Rounding to a step follows the table, in the step's own unit", arguments: RoundingRow.all)
    func roundedToStep_table(row: RoundingRow) {
        #expect(row.weight.rounded(toStep: row.step, row.rule) == row.expected)
    }

    @Test("Pound and kilogram display is stable when a value round-trips through the other unit")
    func lbKgRoundTrip_displayStable() {
        for grams in [0, 1134, 23814, 83915, 108_862, 20412, 20000, 61250, 999_999] {
            let weight = Weight(grams: grams)
            #expect(Weight.pounds(weight.pounds) == weight)
            #expect(Weight.kilograms(weight.kilograms) == weight)
            #expect(Weight.pounds(weight.pounds).formatted(in: .kg) == weight.formatted(in: .kg))
            #expect(Weight.kilograms(weight.kilograms).formatted(in: .lb) == weight.formatted(in: .lb))
        }
    }

    @Test("Weights order by grams")
    func comparable_ordersByGrams() {
        let shuffled: [Weight] = [.pounds(45), .kilograms(20), .zero, .pounds(-5), .kilograms(20.5)]
        #expect(shuffled.sorted() == [.pounds(-5), .zero, .kilograms(20), .pounds(45), .kilograms(20.5)])
        #expect(Weight.kilograms(20) < .pounds(45))
    }

    @Test("Addition, subtraction and zero work on grams")
    func arithmetic_isOnGrams() {
        #expect(Weight(grams: 1500) + Weight(grams: 250) == Weight(grams: 1750))
        #expect(Weight(grams: 1500) - Weight(grams: 2000) == Weight(grams: -500))
        #expect(Weight.zero.grams == 0)
        #expect([Weight(grams: 5), Weight(grams: 7)].reduce(.zero, +) == Weight(grams: 12))
    }

    @Test("Advancing by steps stays on the pound lattice, so loads never drift a gram")
    func advancedBySteps_staysCanonical() {
        #expect(Weight.pounds(250).advanced(bySteps: 7, of: .pounds(5)) == .pounds(285))
        #expect(Weight.pounds(50).advanced(bySteps: 20, of: .pounds(2.5)) == .pounds(100))
        #expect(Weight.pounds(50).grams + 20 * Weight.pounds(2.5).grams != Weight.pounds(100).grams)
        #expect(Weight.kilograms(20).advanced(bySteps: 3, of: .kilograms(1.25)) == .kilograms(23.75))
        #expect(Weight.pounds(45).advanced(bySteps: -2, of: .pounds(2.5)) == .pounds(40))
        #expect(Weight(grams: 20000).advanced(bySteps: 0, of: .pounds(2.5)) == Weight(grams: 20000))
        #expect(Weight(grams: 20000).advanced(bySteps: 4, of: .zero) == Weight(grams: 20000))
    }

    @Test("Scaling multiplies exactly, then rounds to the nearest gram")
    func scaled_roundsToNearestGram() {
        #expect(Weight.pounds(285).scaled(by: dec("0.85")) == Weight(grams: 109_883))
        #expect(Weight(grams: 3).scaled(by: dec("0.5")) == Weight(grams: 2))
        #expect(Weight(grams: -3).scaled(by: dec("0.5")) == Weight(grams: -2))
    }
}

extension WeightTests {
    struct FormatRow: Sendable, CustomStringConvertible {
        let weight: Weight
        let units: Units
        let text: String

        var description: String {
            "\(weight.grams) g in \(units.rawValue) → \(text)"
        }

        static let all: [FormatRow] = [
            FormatRow(weight: .pounds(185), units: .lb, text: "185"),
            FormatRow(weight: .pounds(52.5), units: .lb, text: "52.5"),
            FormatRow(weight: .pounds(46.25), units: .lb, text: "46.25"),
            FormatRow(weight: .zero, units: .lb, text: "0"),
            FormatRow(weight: .pounds(-40), units: .lb, text: "-40"),
            FormatRow(weight: .pounds(1000), units: .lb, text: "1000"),
            FormatRow(weight: .kilograms(1.25), units: .kg, text: "1.25"),
            FormatRow(weight: .kilograms(dec("83.915")), units: .kg, text: "83.9"),
            FormatRow(weight: .pounds(50), units: .kg, text: "22.7"),
            FormatRow(weight: .kilograms(20), units: .lb, text: "44.1"),
            FormatRow(weight: Weight(grams: -181), units: .kg, text: "-0.2")
        ]
    }

    @Test("Formatting prints quarter units exactly and anything else to one decimal", arguments: FormatRow.all)
    func formatted_table(row: FormatRow) {
        #expect(row.weight.formatted(in: row.units) == row.text)
    }

    @Test("The whole-unit presentation rounds half away from zero")
    func wholeValue_roundsToWholeUnit() {
        #expect(Weight(grams: 99507).wholeValue(in: .lb) == 219)
        #expect(Weight.pounds(219.5).wholeValue(in: .lb) == 220)
        #expect(Weight.kilograms(dec("99.4")).wholeValue(in: .kg) == 99)
    }

    @Test("Weight encodes as its grams and decodes back")
    func codable_roundTrips() throws {
        let data = try JSONEncoder().encode(Weight.pounds(185))
        #expect(try Fixtures.json(Weight.pounds(185)) == #"{"grams":83915}"#)
        #expect(try JSONDecoder().decode(Weight.self, from: data) == .pounds(185))
    }

    @Test("Standard pound and kilogram steps, bars and plates are read in their own unit")
    func denominating_standardLattices() {
        for quarters in 1 ... 400 {
            #expect(Units.denominating(.pounds(Decimal(quarters) / 4)) == .lb, "\(quarters) quarter pounds")
        }
        for quarters in 1 ... 240 where quarters != 44 {
            #expect(Units.denominating(.kilograms(Decimal(quarters) / 4)) == .kg, "\(quarters) quarter kilograms")
        }
        #expect(Units.denominating(.kilograms(11)) == .lb, "11 kg is 24.25 lb to the gram (documented)")
    }

    @Test("Pounds round-trip through grams at 0.5 lb resolution", .tags(.property), arguments: PropertySeed.all)
    func poundsRoundTrip_isIdentityAtHalfPound(seed: PropertySeed) {
        var generator = seed.generator
        let halves = Int.random(in: -200 ... 2000, using: &generator)
        let pounds = Decimal(halves) / 2
        let weight = Weight.pounds(pounds)
        #expect(weight.pounds.rounded(scale: 1, .toNearestOrAwayFromZero) == pounds)
        #expect(weight.formatted(in: .lb) == NumberText.fixed(halves * 5, fractionDigits: 1))
    }

    @Test(
        "Rounding to a step is idempotent and lands exactly on a step multiple",
        .tags(.property),
        arguments: PropertySeed.all
    )
    func roundedToStep_isIdempotent(seed: PropertySeed) throws {
        var generator = seed.generator
        let steps: [Weight] = [
            .pounds(5),
            .pounds(2.5),
            .pounds(1.25),
            .kilograms(2.5),
            .kilograms(1.25),
            .kilograms(5)
        ]
        let step = try #require(steps.randomElement(using: &generator))
        let weight = Weight(grams: Int.random(in: -50000 ... 300_000, using: &generator))
        let rounded = weight.rounded(toStep: step)
        let units = Units.denominating(step)
        let multiple = Decimal(rounded.quanta(in: units)) / Decimal(step.quanta(in: units))
        #expect(rounded.rounded(toStep: step) == rounded)
        #expect(multiple.rounded(scale: 0, .toNearestOrAwayFromZero) == multiple)
        // Half a step, plus the ≤ 2.3 g snap to 0.01 lb and the final gram rounding.
        #expect(abs(rounded.grams - weight.grams) <= step.grams / 2 + 3)
    }
}

extension WeightTests {
    struct RoundingRow: Sendable, CustomStringConvertible {
        let weight: Weight
        let step: Weight
        let rule: FloatingPointRoundingRule
        let expected: Weight
        let description: String

        static let all: [RoundingRow] = [
            RoundingRow(
                weight: .pounds(242.25),
                step: .pounds(5),
                rule: .toNearestOrAwayFromZero,
                expected: .pounds(240),
                description: "242.25 lb → 240 lb (criterion 2)"
            ),
            RoundingRow(
                weight: .pounds(242.5),
                step: .pounds(5),
                rule: .toNearestOrAwayFromZero,
                expected: .pounds(245),
                description: "242.5 lb tie → 245 lb (criterion 2)"
            ),
            RoundingRow(
                weight: .pounds(242.5),
                step: .pounds(5),
                rule: .toNearestOrEven,
                expected: .pounds(240),
                description: "242.5 lb, to even → 240 lb"
            ),
            RoundingRow(
                weight: .pounds(242.5),
                step: .pounds(5),
                rule: .down,
                expected: .pounds(240),
                description: "242.5 lb, down → 240 lb"
            ),
            RoundingRow(
                weight: .pounds(241),
                step: .pounds(5),
                rule: .up,
                expected: .pounds(245),
                description: "241 lb, up → 245 lb"
            ),
            RoundingRow(
                weight: .pounds(-2.5),
                step: .pounds(5),
                rule: .toNearestOrAwayFromZero,
                expected: .pounds(-5),
                description: "−2.5 lb tie → −5 lb"
            ),
            RoundingRow(
                weight: .pounds(-2.5),
                step: .pounds(5),
                rule: .towardZero,
                expected: .zero,
                description: "−2.5 lb toward zero → 0"
            ),
            RoundingRow(
                weight: .pounds(-2.5),
                step: .pounds(5),
                rule: .awayFromZero,
                expected: .pounds(-5),
                description: "−2.5 lb away from zero → −5 lb"
            ),
            RoundingRow(
                weight: .pounds(2.5),
                step: .pounds(5),
                rule: .towardZero,
                expected: .zero,
                description: "2.5 lb toward zero → 0"
            ),
            RoundingRow(
                weight: .pounds(2.5),
                step: .pounds(5),
                rule: .awayFromZero,
                expected: .pounds(5),
                description: "2.5 lb away from zero → 5 lb"
            ),
            RoundingRow(
                weight: .kilograms(61.25),
                step: .kilograms(2.5),
                rule: .toNearestOrAwayFromZero,
                expected: .kilograms(62.5),
                description: "61.25 kg tie → 62.5 kg"
            ),
            RoundingRow(
                weight: .kilograms(61.2),
                step: .kilograms(2.5),
                rule: .toNearestOrAwayFromZero,
                expected: .kilograms(60),
                description: "61.2 kg → 60 kg"
            ),
            RoundingRow(
                weight: .pounds(185),
                step: .kilograms(1.25),
                rule: .toNearestOrAwayFromZero,
                expected: .kilograms(83.75),
                description: "185 lb on a 1.25 kg step → 83.75 kg"
            ),
            RoundingRow(
                weight: .pounds(187),
                step: .zero,
                rule: .toNearestOrAwayFromZero,
                expected: .pounds(187),
                description: "a zero step leaves the weight unchanged"
            )
        ]
    }
}
