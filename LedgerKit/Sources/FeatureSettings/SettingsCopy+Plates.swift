import Foundation
import LedgerDomain

/// The words of "Bar and plates" and of its sheet (F14 S2, criterion 3, N12), and of a switch of units that failed
/// (criterion 1, ruling A4).
nonisolated extension SettingsCopy {
    // MARK: Units

    /// Under the title, when a switch of units could not be saved: neither the settings nor the program changed.
    static var switchFailed: String {
        String(
            localized: "Couldn't change the units. Nothing was changed.",
            bundle: .module,
            comment: "Shown on Settings when switching units failed; the settings and the program are as they were"
        )
    }

    /// Beside the failed switch's line: switches again.
    static var tryAgain: String {
        String(localized: "Try again", bundle: .module, comment: "Button on Settings: switch the units again")
    }

    // MARK: Bar and plates

    /// The row of Settings, and the title of its sheet.
    static var barAndPlates: String {
        String(
            localized: "Bar and plates",
            bundle: .module,
            comment: "Settings row and sheet: the bar's weight and the plate sizes the lifter owns"
        )
    }

    /// "45 lb bar": under "Bar and plates" while Plate math is on.
    static func barDetail(_ bar: String, locale: Locale) -> String {
        String(
            localized: "\(bar) bar",
            bundle: .module,
            locale: locale,
            comment: "Under Bar and plates in Settings: the bar's weight with its unit, as 45 lb"
        )
    }

    /// Under "Bar and plates" while Plate math is off, when the row does nothing.
    static var turnOnPlateMath: String {
        String(
            localized: "Turn on Plate math to edit",
            bundle: .module,
            comment: "Under Bar and plates in Settings, while the Plate math switch is off"
        )
    }

    /// "45 lb", "20 kg": a bar or a plate, with its unit.
    static func weight(_ weight: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(weight) lb",
                bundle: .module,
                locale: locale,
                comment: "A bar's or a plate's weight in pounds, in Settings"
            )
        case .kg:
            String(
                localized: "\(weight) kg",
                bundle: .module,
                locale: locale,
                comment: "A bar's or a plate's weight in kilograms, in Settings"
            )
        }
    }

    static var bar: String {
        String(localized: "Bar", bundle: .module, comment: "Bar and plates sheet: the bar's weight, stepped")
    }

    static var platesYouOwn: String {
        String(
            localized: "Plates you own",
            bundle: .module,
            comment: "Bar and plates sheet: above the plate sizes, each switched on or off"
        )
    }

    /// Under the plates when every one is off.
    static var noPlates: String {
        String(
            localized: "No plates: no plate line will show",
            bundle: .module,
            comment: "Bar and plates sheet, when every plate size is off: the set rows will show no plates"
        )
    }

    static var resetToStandard: String {
        String(
            localized: "Reset to standard",
            bundle: .module,
            comment: "Bar and plates sheet: puts back the usual bar and plate sizes of the unit"
        )
    }

    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Bar and plates sheet: saves the bar and the plates")
    }

    /// Also "Delete all data"'s, on its warning and its sheet (S3).
    static var cancel: String {
        String(
            localized: "Cancel",
            bundle: .module,
            comment: "Bar and plates sheet, and Delete all data's warning and sheet: closes it, changing nothing"
        )
    }
}

// MARK: - Counted texts

nonisolated extension Locale {
    /// The locale a spoken weight of the module is written in: the Domain's `forCountedText(in:)` with this module's
    /// catalog, as every module binds it.
    var forCountedText: Locale {
        forCountedText(in: .module)
    }
}
