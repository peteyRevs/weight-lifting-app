import Foundation
import LedgerDomain

// MARK: - The receipt (F13 S2, A3)

/// The receipt's words, FeatureHistory's own copy of F10's (`WorkoutCopy+Receipt`, `WorkoutCopy+Finish`): the same
/// English keys, in this module's catalog (ruling A3). `ReceiptParityTests` (LedgerAppKitTests) pins the detail's
/// receipt equal to F10's, string for string.
nonisolated extension HistoryCopy {
    static var timeTile: String {
        String(localized: "TIME", bundle: .module, comment: "Label of the receipt's tile for how long the workout took")
    }

    static var setsTile: String {
        String(
            localized: "SETS",
            bundle: .module,
            comment: "Label of the receipt's tile for the sets done of all the workout's sets"
        )
    }

    /// "LB MOVED", "KG MOVED": the label of the tile for the weight lifted, in the lifter's units.
    static func movedTile(units: Units) -> String {
        switch units {
        case .lb:
            String(
                localized: "LB MOVED",
                bundle: .module,
                comment: "Label of the receipt's tile for the weight lifted, in pounds"
            )
        case .kg:
            String(
                localized: "KG MOVED",
                bundle: .module,
                comment: "Label of the receipt's tile for the weight lifted, in kilograms"
            )
        }
    }

    /// "23 of 25 sets logged": the sets tile, as VoiceOver reads it.
    static func setsLogged(done: String, of total: Int, locale: Locale) -> String {
        String(
            localized: "\(done) of \(total) sets logged",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "The sets logged in the workout so far, then all its sets"
        )
    }

    /// "24,180 lb moved", "10,968 kg moved": the weight tile, as VoiceOver reads it; the volume is the Domain's text.
    static func moved(_ volume: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(volume) lb moved",
                bundle: .module,
                locale: locale,
                comment: "The total weight lifted in the workout so far, in pounds"
            )
        case .kg:
            String(
                localized: "\(volume) kg moved",
                bundle: .module,
                locale: locale,
                comment: "The total weight lifted in the workout so far, in kilograms"
            )
        }
    }

    /// "1 new PR this session", "3 new PRs this session": the personal records the workout holds.
    static func newRecords(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) new PRs this session",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "The number of personal records the saved workout set"
        )
    }

    static var logged: String {
        String(
            localized: "LOGGED",
            bundle: .module,
            comment: "Heading of the receipt's list of exercises and what was logged"
        )
    }

    static var prescribedOnTheRight: String {
        String(
            localized: "Prescribed on the right",
            bundle: .module,
            comment: "Beside LOGGED: each exercise's prescription stands at the trailing edge of its row"
        )
    }

    /// "Prescribed 5 × 5 @ 185 lb": a row's target, as VoiceOver reads it; the target is the Domain's text.
    static func spokenPrescribed(_ target: String, locale: Locale) -> String {
        String(
            localized: "Prescribed \(target)",
            bundle: .module,
            locale: locale,
            comment: "Spoken: what was prescribed for an exercise of the receipt"
        )
    }

    /// "Logged 5 × 185×5, 185×4": a row's chips, as VoiceOver reads them; the chips are the Domain's text.
    static func spokenLogged(_ chips: String, locale: Locale) -> String {
        String(
            localized: "Logged \(chips)",
            bundle: .module,
            locale: locale,
            comment: "Spoken: the sets logged for an exercise of the receipt"
        )
    }

    static var spokenNothingLogged: String {
        String(
            localized: "Nothing logged",
            bundle: .module,
            comment: "Spoken: an exercise of the receipt with no set logged, drawn as a dash"
        )
    }
}

// MARK: - Delete, and a workout that can't be read (F13 S2)

nonisolated extension HistoryCopy {
    static var deleteWorkout: String {
        String(
            localized: "Delete workout",
            bundle: .module,
            comment: "Button under a past workout's detail: asks before it deletes the workout"
        )
    }

    /// The alert's title (F13 question 8, built to A).
    static var deleteQuestion: String {
        String(
            localized: "Delete this workout?",
            bundle: .module,
            comment: "Title of the alert that asks before a past workout is deleted"
        )
    }

    static var deleteMessage: String {
        String(
            localized: "It's removed from your history, records and stats. This can't be undone.",
            bundle: .module,
            comment: "Under: Delete this workout? in the alert"
        )
    }

    static var delete: String {
        String(localized: "Delete", bundle: .module, comment: "The alert's destructive button: deletes the workout")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "The alert's button that deletes nothing")
    }

    static var deleteFailedTitle: String {
        String(
            localized: "Couldn't delete this workout",
            bundle: .module,
            comment: "Title of the alert shown when a past workout could not be deleted"
        )
    }

    static var deleteFailedBody: String {
        String(
            localized: "It's still in your history. Try again in a moment.",
            bundle: .module,
            comment: "Under: Couldn't delete this workout"
        )
    }

    static var okay: String {
        String(localized: "OK", bundle: .module, comment: "Closes the alert shown when a delete failed")
    }

    /// N10: the detail of a workout this app can't read.
    static var unreadableTitle: String {
        String(
            localized: "This workout can't be read.",
            bundle: .module,
            comment: "Shown in place of a past workout's detail when the workout cannot be read"
        )
    }

    static var unreadableBody: String {
        String(
            localized: "It stays in your history. You can still delete it.",
            bundle: .module,
            comment: "Under: This workout can't be read."
        )
    }
}
