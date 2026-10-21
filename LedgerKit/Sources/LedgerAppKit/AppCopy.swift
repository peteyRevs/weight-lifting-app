import Foundation

/// LedgerAppKit's copy (standards §7): every string the shell shows is looked up here, in this module's
/// `Resources/Localizable.xcstrings`, whose keys are the English text. No other file in the module holds a
/// user-facing literal or a localized lookup; the views are handed these `String`s. A translator's comment is
/// written here, and the catalog's copy of it matches.
nonisolated enum AppCopy {
    /// A tab's title in the tab bar, and the title of the tab's root screen.
    static func title(of tab: AppTab) -> String {
        switch tab {
        case .today:
            String(localized: "Today", bundle: .module, comment: "Tab title, and the title of the Today screen")
        case .program:
            String(localized: "Program", bundle: .module, comment: "Tab title, and the title of the Program screen")
        case .library:
            String(localized: "Library", bundle: .module, comment: "Tab title, and the title of the Library screen")
        case .history:
            String(localized: "History", bundle: .module, comment: "Tab title, and the title of the History screen")
        }
    }

    /// The title of the Settings screen's placeholder, until F14's screen draws its own.
    static var settingsTitle: String {
        String(localized: "Settings", bundle: .module, comment: "Title of the Settings screen")
    }

    /// The title of an exercise's history placeholder, until F12 S2's screen draws its own.
    static var exerciseHistoryTitle: String {
        String(localized: "Exercise history", bundle: .module, comment: "Title of an exercise's history screen")
    }

    /// The title of product decision #29's screen: the database could not be opened.
    static var databaseUnavailableTitle: String {
        String(
            localized: "Can't open your data right now",
            bundle: .module,
            comment: "Title of the screen shown when the database cannot be opened"
        )
    }

    /// The body of product decision #29's screen. It does not name the product (product decisions, Naming).
    static var databaseUnavailableBody: String {
        String(
            localized: "Your workouts are still on this iPhone. The app tries again when you come back to it.",
            bundle: .module,
            comment: "Body of the screen shown when the database cannot be opened"
        )
    }
}
