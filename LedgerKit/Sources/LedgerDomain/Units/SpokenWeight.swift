import Foundation

// Weights and volumes as VoiceOver reads them (F13 S1, A6): the number a screen draws, with the unit's whole word
// in the plural form that number takes, "1 pound", "1.5 pounds", "24,180 pounds". A fixed "%@ pounds" key reads
// "1 pounds"; Foundation's measurement style picks the form, for every language it knows.
//
// Unlike the Domain's other strings these follow a locale: its digits, its grouping and its words. A caller passes
// the locale its own catalog answers in, `forCountedText(in:)` of the injected locale (F13-S1-1): the catalog's
// language with the lifter's region and numbering system, so the unit's word is in the language of the words around
// it ("Mittwoch, 58 minutes, 24.180 Pfund" was two languages; de_DE now reads "58 minutes, 24.180 pounds"). The
// number goes through `Double` only to be written, after it was rounded as the screen rounds it, and a `Double`
// holds every such number exactly enough to print it.

public extension Weight {
    /// "185 pounds", "52.5 kilograms": `formatted(in:)`'s number, spoken. `locale` is the one the caller's catalog
    /// answers in (`forCountedText(in:)`).
    func spoken(in units: Units, locale: Locale) -> String {
        SpokenMass.text(Decimal(string: formatted(in: units)) ?? 0, in: units, locale: locale)
    }
}

public extension Volume {
    /// "24,180 pounds": `formatted(in:)`'s whole number, spoken. `locale` is the one the caller's catalog answers in
    /// (`forCountedText(in:)`).
    func spoken(in units: Units, locale: Locale) -> String {
        SpokenMass.text(Decimal((gramReps / units.gramsPerUnit).roundedToInt()), in: units, locale: locale)
    }
}

enum SpokenMass {
    /// `value` of `units`, written with the measurement style's wide unit in `locale`, to at most two decimals.
    static func text(_ value: Decimal, in units: Units, locale: Locale) -> String {
        let unit: UnitMass = switch units {
        case .lb: .pounds
        case .kg: .kilograms
        }
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0 ... 2)).locale(locale)
        let style = Measurement<UnitMass>.FormatStyle(
            width: .wide,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: number
        )
        return Measurement(value: NSDecimalNumber(decimal: value).doubleValue, unit: unit).formatted(style)
    }
}
