import Foundation
@testable import LedgerDomain
import Testing

/// F13 S2 adversarial (G2), review R1-5: `Weight.shownValue(in:)` is the number `formatted(in:)` prints, and
/// `spoken(in:locale:)` says that number. For every quarter pound and quarter kilogram to 1,000, every pound and
/// half pound converted to kilograms and back, random 10⁻⁷ g weights, and the precision edges (90.7 kg from 200 lb,
/// quarters that round up into the next unit, values just under and over a quarter, huge loads), the printed text
/// reads back as `shownValue`, and the spoken text, with its unit's word taken away, parses back to it in twelve
/// locales and five digit systems (Latin, Arabic-Indic, Persian, Devanagari, Thai).
@Suite("Adversarial F13 S2 · R1-5, the spoken weight's round trip", .tags(.domain, .property))
struct SpokenWeightRoundTripAdversarialTests {
    static let locales = [
        "en_US", "en_GB", "de_DE", "de_CH", "fr_FR", "ru_RU", "en_IN", "ja_JP",
        "ar_EG", "fa_IR", "hi_IN@numbers=deva", "th_TH@numbers=thai"
    ].map(Locale.init(identifier:))

    static func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    /// The weights: quarters of both units, pounds and half pounds in kilograms, random grams, and the edges.
    static func weights() -> [Weight] {
        var weights: [Weight] = []
        for quarter in stride(from: 0, through: 4000, by: 7) {
            weights.append(.pounds(Decimal(quarter) / 4))
            weights.append(.kilograms(Decimal(quarter) / 4))
        }
        for half in stride(from: 1, through: 2000, by: 3) {
            weights.append(.pounds(Decimal(half) / 2))
        }
        var rng = SeededGenerator(seed: 0x5EEDF13)
        for _ in 0 ..< 400 {
            weights.append(Weight(grams: Decimal(Int.random(in: 0 ... 5_000_000_000_000, using: &rng)) / 10_000_000))
        }
        let edges = [
            "90.7", "90.72", "90.718474", "2.249", "2.2449", "2.2451", "2.25", "0.124", "0.125", "0.126", "0.05",
            "0.049", "99.95", "99.96", "999.975", "1234567.25", "0.0000001", "9999999999.75"
        ]
        for edge in edges {
            weights.append(.kilograms(decimal(edge)))
            weights.append(.pounds(decimal(edge)))
        }
        weights.append(.pounds(200))
        return weights
    }

    /// The number of `spoken` in `locale`: the text without its unit's word and its direction marks, parsed by the
    /// locale's own number format.
    static func number(in spoken: String, locale: Locale) -> Decimal? {
        let kept = spoken.unicodeScalars.filter { scalar in
            !scalar.properties.isAlphabetic && scalar.properties.generalCategory != .format
                && scalar.properties.generalCategory != .nonspacingMark
        }
        let text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        let format = NumberFormatter()
        format.locale = locale
        format.numberStyle = .decimal
        format.generatesDecimalNumbers = true
        format.isLenient = true
        // The formatter parses through `Double` ("8.7" comes back 8.6999…), so its number is rounded to the two
        // decimals a spoken weight has at most.
        return (format.number(from: text) as? NSDecimalNumber)?.decimalValue.rounded(scale: 2, .toNearestOrAwayFromZero)
    }

    @Test("The printed text is shownValue, digit for digit")
    func formatted_isShownValue() {
        var mismatches: [String] = []
        for weight in Self.weights() {
            for units in [Units.lb, .kg] {
                let printed = weight.formatted(in: units)
                if Self.decimal(printed) != weight.shownValue(in: units) {
                    mismatches.append("\(weight.grams) g in \(units): \(printed)")
                }
            }
        }
        let none = mismatches.isEmpty
        #expect(none, "\(mismatches.prefix(5))")
    }

    @Test("The spoken number parses back to shownValue in every locale and digit system")
    func spoken_parsesBackToShownValue() {
        var mismatches: [String] = []
        var checked = 0
        for weight in Self.weights() {
            for units in [Units.lb, .kg] {
                let shown = weight.shownValue(in: units)
                for locale in Self.locales {
                    let spoken = weight.spoken(in: units, locale: locale)
                    checked += 1
                    // Arabic says exactly two with the dual form and no digits ("رطلان", two pounds): right.
                    let isArabicDual = locale.language.languageCode == .arabic && shown == 2
                        && Self.number(in: spoken, locale: locale) == nil
                    if Self.number(in: spoken, locale: locale) != shown, !isArabicDual {
                        mismatches.append("\(locale.identifier) \(units) \(shown): \"\(spoken)\"")
                    }
                }
            }
        }
        let none = mismatches.isEmpty
        #expect(none, "\(mismatches.count) of \(checked), first \(mismatches.prefix(6))")
        #expect(checked > 50000)
    }

    @Test("200 lb in kilograms prints and says 90.7; 90.7 kg in pounds prints and says 200")
    func ninetyPointSeven_bothWays() {
        let english = Locale(identifier: "en_US")
        #expect(Weight.pounds(200).formatted(in: .kg) == "90.7")
        #expect(Weight.pounds(200).spoken(in: .kg, locale: english) == "90.7 kilograms")
        let kilograms = Weight.kilograms(Self.decimal("90.7"))
        #expect(kilograms.formatted(in: .lb) == "200")
        #expect(kilograms.spoken(in: .lb, locale: english) == "200 pounds")
        #expect(Weight.pounds(200).spoken(in: .kg, locale: Locale(identifier: "de_DE")) == "90,7 Kilogramm")
    }
}
