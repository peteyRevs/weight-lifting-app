import Foundation

/// LedgerAppKit's copy (standards §7): every string the shell shows is looked up here, in this module's
/// `Resources/Localizable.xcstrings`, whose keys are the English text. No other file in the module holds a
/// user-facing literal or a localized lookup; the views are handed these `String`s.
nonisolated enum AppCopy {
    /// A tab's title in the tab bar, and the title of the tab's root screen.
    static func title(of tab: AppTab) -> String {
        switch tab {
        case .today: String(localized: "Today", bundle: .module)
        case .program: String(localized: "Program", bundle: .module)
        case .library: String(localized: "Library", bundle: .module)
        case .history: String(localized: "History", bundle: .module)
        }
    }

    /// The title of a pushed screen whose feature has not landed yet.
    static func title(of destination: AppDestination) -> String {
        switch destination {
        case .settings: String(localized: "Settings", bundle: .module)
        }
    }

    /// The title of product decision #29's screen: the database could not be opened.
    static var databaseUnavailableTitle: String {
        String(localized: "Can't open your data right now", bundle: .module)
    }

    /// The body of product decision #29's screen.
    static var databaseUnavailableBody: String {
        String(
            localized: "Your workouts are still on this iPhone. Ledger tries again when you come back to it.",
            bundle: .module
        )
    }
}
