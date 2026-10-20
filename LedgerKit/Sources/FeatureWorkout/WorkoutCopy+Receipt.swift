import Foundation
import LedgerDomain

// MARK: - The receipt (F10 S7b)

nonisolated extension WorkoutCopy {
    static var done: String {
        String(
            localized: "Done",
            bundle: .module,
            comment: "Closes the receipt of a saved workout and returns to Today"
        )
    }

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

    /// "LB MOVED", "KG MOVED": the label of the tile for the weight lifted, in the workout's units.
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

    /// "1 new PR this session", "3 new PRs this session": the personal records the workout set.
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

    // MARK: Spoken only (the three texts are the product owner's to confirm)

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
