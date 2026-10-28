import Foundation
import LedgerDomain

/// FeatureHistory's copy (standards §7): every text the History tab shows or speaks is looked up here, in this
/// module's `Resources/Localizable.xcstrings`, whose keys are the English text. No other file of the module holds a
/// user-facing literal or a lookup; `HistoryPresentation` is handed these `String`s and joins fragments with " · ".
/// A member whose key carries a value takes the locale its caller was given.
///
/// Not here: workout names, which are data; weights and volumes, which the Domain formats and speaks; dates, which
/// `Date.FormatStyle` writes in the injected locale.
nonisolated enum HistoryCopy {
    static var title: String {
        String(localized: "History", bundle: .module, comment: "Title of the History tab's screen")
    }

    // MARK: Rows

    /// "58 min": a workout's length in whole minutes, on its row.
    static func minutes(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) min",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "On a past workout's row: its length in whole minutes, abbreviated"
        )
    }

    /// "58 minutes": the same length, as VoiceOver reads it.
    static func spokenMinutes(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) minutes",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Spoken length of a past workout, in whole minutes"
        )
    }

    /// "24,180 lb": a workout's volume, on its row.
    static func volume(_ volume: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(volume) lb",
                bundle: .module,
                locale: locale,
                comment: "On a past workout's row: the weight it moved, in pounds"
            )
        case .kg:
            String(
                localized: "\(volume) kg",
                bundle: .module,
                locale: locale,
                comment: "On a past workout's row: the weight it moved, in kilograms"
            )
        }
    }

    /// "1 PR", "3 PRs": the personal records a workout holds, its row's badge and the end of what VoiceOver reads.
    static func records(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) PRs",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Badge on a past workout's row: how many personal records it set"
        )
    }

    // MARK: Messages

    static var noWorkoutsYet: String {
        String(localized: "No workouts yet.", bundle: .module, comment: "Title shown in History before any workout")
    }

    static var noWorkoutsBody: String {
        String(
            localized: "Finish a workout and it shows up here.",
            bundle: .module,
            comment: "Under: No workouts yet. in History"
        )
    }

    static var goToToday: String {
        String(
            localized: "Go to Today",
            bundle: .module,
            comment: "Button under the empty History: it shows the Today tab"
        )
    }

    static var failedTitle: String {
        String(
            localized: "Can't show your history right now",
            bundle: .module,
            comment: "Title shown in place of History when its workouts cannot be read"
        )
    }

    static var failedBody: String {
        String(
            localized: "Your workouts are still on this iPhone. Open the app again to try once more.",
            bundle: .module,
            comment: "Under the title shown when History's workouts cannot be read"
        )
    }
}

// MARK: - Counted texts

nonisolated extension Locale {
    /// The locale every counted text of the module is looked up with: the Domain's `forCountedText(in:)`, the one
    /// place that decides it, with this module's catalog.
    var forCountedText: Locale {
        forCountedText(in: .module)
    }
}
