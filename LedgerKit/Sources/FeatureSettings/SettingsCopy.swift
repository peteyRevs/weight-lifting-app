import Foundation
import LedgerDomain

/// FeatureSettings' copy (standards §7): every text Settings shows or speaks is looked up here, in this module's
/// `Resources/Localizable.xcstrings`, whose keys are the English text. No other file of the module holds a
/// user-facing literal or a lookup; `SettingsPresentation` is handed these `String`s. A member whose key carries a
/// value takes the locale its caller was given. The names of the units and the About line are in
/// `SettingsCopy+Names.swift`.
///
/// Not here: the rest's drawn value, which the Domain writes (`RestDuration.label`), and the weekdays' names,
/// which the lifter's calendar gives.
nonisolated enum SettingsCopy {
    // MARK: Header

    static var title: String {
        String(localized: "Settings", bundle: .module, comment: "Title of the Settings screen")
    }

    /// Shown under the title when a change could not be saved; the control it came from shows the stored value
    /// again.
    static var saveFailed: String {
        String(
            localized: "Couldn't save that change.",
            bundle: .module,
            comment: "Shown on Settings when a change could not be saved; the setting goes back to what it was"
        )
    }

    // MARK: Training

    static var training: String {
        String(localized: "TRAINING", bundle: .module, comment: "Heading of Settings' training preferences")
    }

    static var units: String {
        String(
            localized: "Units",
            bundle: .module,
            comment: "Settings row: pounds or kilograms; also the spoken name of its two-option control"
        )
    }

    static var unitsDetail: String {
        String(
            localized: "Applies to every log and chart",
            bundle: .module,
            comment: "Under Units in Settings"
        )
    }

    static var defaultRest: String {
        String(
            localized: "Default rest",
            bundle: .module,
            comment: "Settings row: the rest between sets a new exercise starts with"
        )
    }

    static var defaultRestDetail: String {
        String(localized: "Used for new exercises", bundle: .module, comment: "Under Default rest in Settings")
    }

    static var weekStart: String {
        String(
            localized: "Week starts on",
            bundle: .module,
            comment: "Settings row: the weekday a week starts on, chosen from a menu of the seven"
        )
    }

    static var weekStartDetail: String {
        String(
            localized: "For the week strip and the week's totals",
            bundle: .module,
            comment: "Under Week starts on in Settings: what the first day of the week changes"
        )
    }

    static var plateMath: String {
        String(
            localized: "Plate math",
            bundle: .module,
            comment: "Settings switch: show the plates to load on each side of the bar"
        )
    }

    static var plateMathDetail: String {
        String(
            localized: "Show the plates per side on each set",
            bundle: .module,
            comment: "Under the Plate math switch in Settings"
        )
    }

    static var autoRest: String {
        String(
            localized: "Auto rest timer",
            bundle: .module,
            comment: "Settings switch: start the rest timer when a set is logged"
        )
    }

    static var autoRestDetail: String {
        String(
            localized: "Start the clock when a set is logged",
            bundle: .module,
            comment: "Under the Auto rest timer switch in Settings"
        )
    }

    static var watchBuzz: String {
        String(
            localized: "Watch haptic at zero",
            bundle: .module,
            comment: "Settings switch: the Apple Watch taps the wrist when the rest timer reaches zero"
        )
    }

    static var watchBuzzDetail: String {
        String(
            localized: "Buzz the wrist when rest ends",
            bundle: .module,
            comment: "Under the Watch haptic at zero switch in Settings"
        )
    }

    // MARK: Data

    static var data: String {
        String(
            localized: "DATA",
            bundle: .module,
            comment: "Heading of Settings' rows about the lifter's data: Apple Health"
        )
    }

    static var appleHealth: String {
        String(localized: "Apple Health", bundle: .module, comment: "Settings row: the link to Apple Health")
    }

    /// The Health row's status until the link to Apple Health is built (F16; Pete's question 4, A).
    static var notConnected: String {
        String(
            localized: "Not connected",
            bundle: .module,
            comment: "Status beside Apple Health in Settings: the app does not write to Apple Health"
        )
    }

    /// Debug builds only: the row that opens the Debug menu.
    static var diagnostics: String {
        String(
            localized: "Diagnostics",
            bundle: .module,
            comment: "Settings row in test builds only: opens the developer menu"
        )
    }
}
