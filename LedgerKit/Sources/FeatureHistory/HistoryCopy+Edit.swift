import Foundation
import LedgerDomain

// MARK: - The sheet that fixes a past workout's sets (F13 S3)

nonisolated extension HistoryCopy {
    /// In the bar of a past workout's detail (F13 question 2, built to A).
    static var edit: String {
        String(
            localized: "Edit",
            bundle: .module,
            comment: "Button in the bar of a past workout's detail: opens the sheet that fixes its sets"
        )
    }

    static var editSetsTitle: String {
        String(localized: "Edit sets", bundle: .module, comment: "Title of the sheet that fixes a past workout's sets")
    }

    static var save: String {
        String(localized: "Save", bundle: .module, comment: "Stores the sets the sheet changed")
    }

    /// "Set 2 weight": the name of a logged set's weight stepper, its number among the exercise's logged sets.
    static func setWeight(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Set \(number) weight",
            bundle: .module,
            locale: locale,
            comment: "Name of the stepper that fixes the weight of a logged set"
        )
    }

    /// "Set 2 reps".
    static func setReps(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Set \(number) reps",
            bundle: .module,
            locale: locale,
            comment: "Name of the stepper that fixes the reps of a logged set"
        )
    }

    /// A save that failed: the line at the sheet's foot, which stays up.
    static var saveFailed: String {
        String(
            localized: "Couldn't save your changes. Try again in a moment.",
            bundle: .module,
            comment: "At the foot of the sheet that fixes a past workout's sets, when they could not be stored"
        )
    }

    /// N12: a save found the workout deleted meanwhile.
    static var workoutGoneTitle: String {
        String(
            localized: "This workout was deleted",
            bundle: .module,
            comment: "Title of the alert shown when a past workout was deleted while its sets were being fixed"
        )
    }

    static var workoutGoneBody: String {
        String(
            localized: "Your changes weren't saved.",
            bundle: .module,
            comment: "Under: This workout was deleted"
        )
    }
}
