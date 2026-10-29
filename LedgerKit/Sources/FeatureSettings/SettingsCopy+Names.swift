import Foundation
import LedgerDomain

/// The units' names and the About line's parts (`SettingsCopy`; standards §7: each module holds its own entry for a
/// Domain case).
nonisolated extension SettingsCopy {
    /// "LB", "KG": an option of the units' control, as the prototype writes it.
    static func unitsOption(_ units: Units) -> String {
        switch units {
        case .lb: String(localized: "LB", bundle: .module, comment: "Units option in Settings: pounds, abbreviated")
        case .kg: String(
                localized: "KG",
                bundle: .module,
                comment: "Units option in Settings: kilograms, abbreviated"
            )
        }
    }

    /// "pounds", "kilograms": what VoiceOver reads for "LB" and "KG".
    static func spokenUnits(_ units: Units) -> String {
        switch units {
        case .lb: String(localized: "pounds", bundle: .module, comment: "Spoken name of the LB option in Settings")
        case .kg: String(
                localized: "kilograms",
                bundle: .module,
                comment: "Spoken name of the KG option in Settings"
            )
        }
    }

    // MARK: About

    // The About line's values are the bundle's text, put in as they are, so the locale each lookup takes changes
    // nothing today. It is kept because standards §7 has every lookup whose key carries a value pass its caller's
    // locale (`ModuleCopyTests`' audit fails one that does not), so a value that is a number later is formatted in it.

    /// "Ledger 0.14.0": the About line's first part, the app's name, then its version.
    static func nameAndVersion(_ name: String, _ version: String, locale: Locale) -> String {
        String(
            localized: "\(name) \(version)",
            bundle: .module,
            locale: locale,
            comment: "Foot of Settings: the app's name, then its version; reorder them with %1$@ and %2$@"
        )
    }

    /// "Version 0.14.0": the About line's first part when the app's name cannot be read.
    static func version(_ version: String, locale: Locale) -> String {
        String(
            localized: "Version \(version)",
            bundle: .module,
            locale: locale,
            comment: "Foot of Settings when the app's name is unknown: the version number"
        )
    }

    /// "build 74": the About line's last part.
    static func build(_ build: String, locale: Locale) -> String {
        String(
            localized: "build \(build)",
            bundle: .module,
            locale: locale,
            comment: "Foot of Settings, after the app's name and version: the build number"
        )
    }

    /// The About line when neither the version nor the build can be read.
    static var versionUnknown: String {
        String(
            localized: "Version unknown",
            bundle: .module,
            comment: "Foot of Settings when the app's version and build cannot be read"
        )
    }
}
