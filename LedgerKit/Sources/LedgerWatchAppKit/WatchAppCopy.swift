import Foundation

/// LedgerWatchAppKit's copy (standards §7): every string the watch's shell shows is looked up here, in this
/// module's `Resources/Localizable.xcstrings`, whose keys are the English text. No other file in the module holds a
/// user-facing literal or a localized lookup; the views are handed these `String`s. A translator's comment is
/// written here, and the catalog's copy of it matches.
nonisolated enum WatchAppCopy {
    /// The title of the watch's Today screen; the placeholder shows it alone until F18 replaces the screen.
    static var today: String {
        String(localized: "Today", bundle: .module, comment: "Title of the watch's Today screen")
    }

    /// The title of product decision #29's screen: the database could not be opened.
    static var databaseUnavailableTitle: String {
        String(
            localized: "Can't open your data right now",
            bundle: .module,
            comment: "Title of the watch screen shown when the database cannot be opened"
        )
    }

    static var databaseUnavailableBody: String {
        String(
            localized: "Your workouts are still on this watch. The app tries again when you come back to it.",
            bundle: .module,
            comment: "Under the title shown when the database cannot be opened, on the watch"
        )
    }
}
