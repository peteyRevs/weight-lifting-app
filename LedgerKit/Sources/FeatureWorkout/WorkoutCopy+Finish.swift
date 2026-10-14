import Foundation
import LedgerDomain

// MARK: - "End workout?" and the save (F10 S7)

nonisolated extension WorkoutCopy {
    static var endWorkout: String {
        String(localized: "End workout?", bundle: .module, comment: "Title of the sheet the Finish button opens")
    }

    static var saveWorkout: String {
        String(localized: "Save workout", bundle: .module, comment: "Ends the workout and keeps it in history")
    }

    static var discard: String {
        String(localized: "Discard", bundle: .module, comment: "Ends the workout without saving it")
    }

    static var keepLifting: String {
        String(localized: "Keep lifting", bundle: .module, comment: "Closes the sheet and returns to the workout")
    }

    /// "23 of 25 sets logged": the sets done, as text in the lifter's digits, of the workout's set rows,
    /// whose number picks the form.
    static func setsLogged(done: String, of total: Int, locale: Locale) -> String {
        String(
            localized: "\(done) of \(total) sets logged",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "The sets logged in the workout so far, then all its sets"
        )
    }

    /// "24,180 lb moved", "10,968 kg moved": the weight lifted so far, the Domain's text.
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

    // MARK: A save that did not go through (the three texts are the product owner's to confirm, O4)

    static var couldNotSaveWorkout: String {
        String(localized: "Couldn't save this workout", bundle: .module)
    }

    static var stillOnThisPhone: String {
        String(
            localized: "It's still on this iPhone. Try again.",
            bundle: .module,
            comment: "Shown when a finished workout could not be saved: nothing of it is lost"
        )
    }

    /// The button; "Try again." with its full stop is a sentence of the failure lines.
    static var tryAgainButton: String {
        String(localized: "Try again", bundle: .module, comment: "Button that saves the workout again")
    }
}
