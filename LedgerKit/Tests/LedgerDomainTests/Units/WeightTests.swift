import Foundation
@testable import LedgerDomain
import Testing

@Suite("Weight", .tags(.domain))
struct WeightTests {
    @Test("Pounds and kilograms convert to exact grams with no rounding (criterion 1, ADR-007)")
    func pounds_toGrams_exact() {
        #expect(Weight.pounds(185).grams == dec("83914.58845"))
        #expect(Weight.pounds(1).grams == dec("453.59237"))
        #expect(Weight.pounds(2.5).grams == dec("1133.980925"))
        #expect(Weight.pounds(dec("453.59237")).grams == dec("205746.0381222169"))
        #expect(Weight.kilograms(dec("83.915")).grams == 83915)
        #expect(Weight.kilograms(dec("0.0025")).grams == dec("2.5"))
        #expect(Weight.pounds(185).formatted(in: .lb) == "185")
        #expect(Weight.pounds(185).formatted(in: .kg) == "83.9")
    }

    @Test("Values read back exactly in either unit")
    func value_inUnits_isExact() {
        #expect(Weight(grams: 1000).kilograms == 1)
        #expect(Weight(grams: 453_592).value(in: .kg) == dec("453.592"))
        #expect(Weight.pounds(5).pounds == 5)
        #expect(Weight.pounds(dec("180.625")).pounds == dec("180.625"))
        #expect(Weight(grams: 45_359_237).pounds == 100_000)
    }

    @Test("Rounding to a step follows the table, exactly (rules 12, 15; decision #3)", arguments: RoundingRow.all)
    func roundedToStep_table(row: RoundingRow) {
        #expect(row.weight.rounded(toStep: row.step, row.rule) == row.expected)
    }

    @Test("Pound and kilogram display is stable when a value round-trips through the other unit")
    func lbKgRoundTrip_displayStable() {
        let grams: [Weight] = [Weight(grams: 1134), Weight(grams: 23814), Weight(grams: 999_999)]
        let samples: [Weight] = [.zero, .pounds(2.5), .pounds(185), .pounds(dec("46.25")), .kilograms(20)] + grams
        for weight in samples {
            let viaPounds = Weight.pounds(weight.pounds)
            let viaKilograms = Weight.kilograms(weight.kilograms)
            #expect(viaKilograms == weight)
            #expect(abs(viaPounds.grams - weight.grams) < dec("0.000000000000000000000001"))
            for units in Units.allCases {
                #expect(viaPounds.formatted(in: units) == weight.formatted(in: units))
                #expect(viaKilograms.formatted(in: units) == weight.formatted(in: units))
            }
        }
        #expect(Weight.pounds(Weight.pounds(185).pounds) == .pounds(185))
    }

    @Test("Weights order by grams")
    func comparable_ordersByGrams() {
        let shuffled: [Weight] = [.pounds(45), .kilograms(20), .zero, .pounds(-5), .kilograms(20.5)]
        #expect(shuffled.sorted() == [.pounds(-5), .zero, .kilograms(20), .pounds(45), .kilograms(20.5)])
        #expect(Weight.kilograms(20) < .pounds(45))
    }

    @Test("Equality and hashing are numeric: 1 g == 1.00 g, and sums equal their literal")
    func equality_isNumeric_hashesAgree() {
        let pairs: [(Weight, Weight)] = [
            (Weight(grams: 1), Weight(grams: dec("1.00"))),
            (.pounds(2.5) + .pounds(2.5), .pounds(5)),
            (.kilograms(dec("0.1")) + .kilograms(dec("0.2")), .kilograms(dec("0.3"))),
            (.pounds(dec("212.5")).scaled(by: dec("0.85")), .pounds(dec("180.625")))
        ]
        for (left, right) in pairs {
            #expect(left == right)
            #expect(left.hashValue == right.hashValue)
        }
        #expect(Set(pairs.flatMap { [$0.0, $0.1] }).count == pairs.count)
    }

    @Test("Addition, subtraction and zero are exact")
    func arithmetic_isOnGrams() {
        #expect(Weight(grams: 1500) + Weight(grams: 250) == Weight(grams: 1750))
        #expect(Weight(grams: 1500) - Weight(grams: 2000) == Weight(grams: -500))
        #expect(Weight.zero.grams == 0)
        #expect([Weight(grams: 5), Weight(grams: 7)].reduce(.zero, +) == Weight(grams: 12))
    }

    @Test("Stepping and adding never drift: 185 lb + 6 × 2.5 lb is exactly 200 lb (ADR-007)")
    func arithmetic_noDrift() {
        #expect(Weight.pounds(250).advanced(bySteps: 7, of: .pounds(5)) == .pounds(285))
        #expect(Weight.pounds(50).advanced(bySteps: 20, of: .pounds(2.5)) == .pounds(100))
        #expect((0 ..< 6).reduce(Weight.pounds(185)) { total, _ in total + .pounds(2.5) } == .pounds(200))
        #expect(Weight.kilograms(20).advanced(bySteps: 3, of: .kilograms(1.25)) == .kilograms(23.75))
        #expect(Weight.pounds(45).advanced(bySteps: -2, of: .pounds(2.5)) == .pounds(40))
        #expect(Weight(grams: 20000).advanced(bySteps: 0, of: .pounds(2.5)) == Weight(grams: 20000))
        #expect(Weight(grams: 20000).advanced(bySteps: 4, of: .zero) == Weight(grams: 20000))
    }

    @Test("Scaling is the exact product; only rounded(toStep:) rounds (rules 12, 15)")
    func scaled_isExact() {
        #expect(Weight.pounds(285).scaled(by: dec("0.85")) == .pounds(dec("242.25")))
        #expect(Weight(grams: 3).scaled(by: dec("0.5")) == Weight(grams: dec("1.5")))
        #expect(Weight(grams: -3).scaled(by: dec("0.5")) == Weight(grams: dec("-1.5")))
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

    @Test("Weight encodes as the exact decimal text of its grams and rejects anything else")
    func codable_exactDecimalText() throws {
        #expect(try Fixtures.json(Weight.pounds(185)) == #"{"grams":"83914.58845"}"#)
        #expect(try Fixtures.json(Weight(grams: dec("-0.5"))) == #"{"grams":"-0.5"}"#)
        for weight in [Weight.pounds(185), .kilograms(dec("-12.345")), .zero, Weight(grams: dec("1e-20"))] {
            #expect(try JSONDecoder().decode(Weight.self, from: JSONEncoder().encode(weight)) == weight)
        }
        for bad in [
            #"{"grams":83915}"#,
            #"{"grams":"1e3"}"#,
            #"{"grams":"NaN"}"#,
            #"{"grams":"12abc"}"#,
            #"{"grams":"1,5"}"#,
            #"{"grams":"."}"#,
            #"{"grams":"-"}"#,
            #"{"grams":""}"#
        ] {
            #expect(throws: DecodingError.self, "\(bad)") {
                try JSONDecoder().decode(Weight.self, from: Data(bad.utf8))
            }
        }
    }

    @Test("Text that Decimal cannot hold exactly is rejected, and a NaN weight cannot encode (review N3, N4)")
    func codable_rejectsInexactTextAndNaN() throws {
        let tooLong = #"{"grams":"1234567890123456789012345678901234567890.5"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Weight.self, from: Data(tooLong.utf8)) }
        let padded = try JSONDecoder().decode(Weight.self, from: Data(#"{"grams":"-007.500"}"#.utf8))
        #expect(padded == Weight(grams: dec("-7.5")))
        #expect(throws: EncodingError.self) { try JSONEncoder().encode(Weight(grams: .nan)) }
        #expect(throws: EncodingError.self) { try JSONEncoder().encode(Volume(gramReps: .nan)) }
    }

    @Test("Formatting renders Decimal digits, so huge weights print correctly (review N4)")
    func formatted_hugeValues_printDigits() {
        #expect(Weight.pounds(dec("1000000000000000000")).formatted(in: .lb) == "1000000000000000000")
        #expect(Weight.pounds(dec("-12345678901234567890.25")).formatted(in: .lb) == "-12345678901234567890.25")
        #expect(Weight.kilograms(dec("0.04")).formatted(in: .kg) == "0")
        #expect(Weight.kilograms(dec("-0.04")).formatted(in: .kg) == "0")
    }

    @Test("Bugs A and C: exact multiples and exact ties no longer depend on unit inference or gram noise")
    func roundedToStep_exactTiesAndMultiples() {
        // 33 = 3 × 11 kg is already a multiple (bug A); 212.5 × 0.85 = 180.625 lb = 144.5 × 1.25 lb (bug C).
        #expect(Weight.kilograms(33).rounded(toStep: .kilograms(11)) == .kilograms(33))
        let deload = Weight.pounds(dec("212.5")).scaled(by: dec("0.85"))
        #expect(deload.rounded(toStep: .pounds(1.25)) == .pounds(dec("181.25")))
        #expect(deload.rounded(toStep: .pounds(1.25), .toNearestOrEven) == .pounds(180))
    }

    @Test("Pounds round-trip through grams exactly at 0.5 lb resolution", .tags(.property), arguments: PropertySeed.all)
    func poundsRoundTrip_isIdentityAtHalfPound(seed: PropertySeed) {
        var generator = seed.generator
        let halves = Int.random(in: -200 ... 2000, using: &generator)
        let pounds = Decimal(halves) / 2
        let weight = Weight.pounds(pounds)
        #expect(weight.pounds == pounds)
        #expect(weight.formatted(in: .lb) == NumberText.fixed(halves * 5, fractionDigits: 1))
    }

    @Test(
        "Rounding to a step is idempotent, lands exactly on a step multiple and moves at most half a step",
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
            .kilograms(11)
        ]
        let step = try #require(steps.randomElement(using: &generator))
        let weight = Weight.pounds(Decimal(Int.random(in: -50000 ... 70000, using: &generator)) / 100)
        let rounded = weight.rounded(toStep: step)
        let multiple = rounded.grams / step.grams
        #expect(rounded.rounded(toStep: step) == rounded)
        #expect(multiple.rounded(scale: 0, .toNearestOrAwayFromZero) == multiple)
        #expect(abs(rounded.grams - weight.grams) * 2 <= step.grams)
    }
}

extension WeightTests {
    struct RoundingRow: Sendable, CustomStringConvertible {
        let weight: Weight
        let step: Weight
        let rule: FloatingPointRoundingRule
        let expected: Weight
        let description: String

        init(
            _ weight: Weight,
            _ step: Weight,
            _ rule: FloatingPointRoundingRule,
            _ expected: Weight,
            _ description: String
        ) {
            self.weight = weight
            self.step = step
            self.rule = rule
            self.expected = expected
            self.description = description
        }

        static let all: [RoundingRow] = [
            RoundingRow(
                .pounds(242.25),
                .pounds(5),
                .toNearestOrAwayFromZero,
                .pounds(240),
                "242.25 lb → 240 lb (criterion 2)"
            ),
            RoundingRow(
                .pounds(242.5),
                .pounds(5),
                .toNearestOrAwayFromZero,
                .pounds(245),
                "242.5 lb tie → 245 lb (criterion 2)"
            ),
            RoundingRow(.pounds(242.5), .pounds(5), .toNearestOrEven, .pounds(240), "242.5 lb, to even → 240 lb"),
            RoundingRow(.pounds(242.5), .pounds(5), .down, .pounds(240), "242.5 lb, down → 240 lb"),
            RoundingRow(.pounds(241), .pounds(5), .up, .pounds(245), "241 lb, up → 245 lb"),
            RoundingRow(.pounds(-2.5), .pounds(5), .toNearestOrAwayFromZero, .pounds(-5), "−2.5 lb tie → −5 lb"),
            RoundingRow(.pounds(-2.5), .pounds(5), .towardZero, .zero, "−2.5 lb toward zero → 0"),
            RoundingRow(.pounds(-2.5), .pounds(5), .awayFromZero, .pounds(-5), "−2.5 lb away from zero → −5 lb"),
            RoundingRow(.pounds(2.5), .pounds(5), .towardZero, .zero, "2.5 lb toward zero → 0"),
            RoundingRow(.pounds(2.5), .pounds(5), .awayFromZero, .pounds(5), "2.5 lb away from zero → 5 lb"),
            RoundingRow(
                .kilograms(61.25),
                .kilograms(2.5),
                .toNearestOrAwayFromZero,
                .kilograms(62.5),
                "61.25 kg tie → 62.5 kg"
            ),
            RoundingRow(
                .kilograms(dec("61.2")),
                .kilograms(2.5),
                .toNearestOrAwayFromZero,
                .kilograms(60),
                "61.2 kg → 60 kg"
            ),
            RoundingRow(
                .pounds(185),
                .kilograms(1.25),
                .toNearestOrAwayFromZero,
                .kilograms(83.75),
                "185 lb on a 1.25 kg step → 83.75 kg"
            ),
            RoundingRow(
                .pounds(187),
                .zero,
                .toNearestOrAwayFromZero,
                .pounds(187),
                "a zero step leaves the weight unchanged"
            )
        ]
    }
}
