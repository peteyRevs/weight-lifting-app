import Foundation
import LedgerDomain

// MARK: - The exercise card and the remaining exercises (F10 S5)

nonisolated extension WorkoutCopy {
    static var target: String {
        String(localized: "TARGET", bundle: .module, comment: "Label before what the program prescribes")
    }

    /// "5 × 5 @ 185 lb · RPE 8".
    static func targetPounds(sets: Int, reps: Int, load: String, rpe: String, locale: Locale) -> String {
        String(
            localized: "\(sets) × \(reps) @ \(load) lb · RPE \(rpe)",
            bundle: .module,
            locale: locale,
            comment: "What the program prescribes: sets, reps, the load in pounds, then the effort from 5 to 10"
        )
    }

    /// "5 × 5 @ 85 kg · RPE 8".
    static func targetKilograms(sets: Int, reps: Int, load: String, rpe: String, locale: Locale) -> String {
        String(
            localized: "\(sets) × \(reps) @ \(load) kg · RPE \(rpe)",
            bundle: .module,
            locale: locale,
            comment: "What the program prescribes: sets, reps, the load in kilograms, then the effort from 5 to 10"
        )
    }

    static var last: String {
        String(localized: "Last", bundle: .module, comment: "Label before what was done in the last workout")
    }

    static var noHistoryYet: String {
        String(localized: "No history yet", bundle: .module, comment: "Shown after Last for an exercise never logged")
    }

    static var repeatLast: String {
        String(
            localized: "Repeat",
            bundle: .module,
            comment: "Button that gives every set the last workout's weight and reps"
        )
    }

    static var numberColumn: String {
        String(localized: "#", bundle: .module, comment: "Heading of the column of set numbers")
    }

    static var repsColumn: String {
        String(localized: "reps", bundle: .module, comment: "Heading of the column of repetitions")
    }

    /// "lb" or "kg": the heading of the weight column.
    static func unit(_ units: Units) -> String {
        switch units {
        case .lb: String(localized: "lb", bundle: .module, comment: "Pounds, as a column heading")
        case .kg: String(localized: "kg", bundle: .module, comment: "Kilograms, as a column heading")
        }
    }

    static var dropSetLabel: String {
        String(localized: "D", bundle: .module, comment: "A drop set's label in the column of set numbers")
    }

    /// "5 LB", "2.5 KG": what one tap on a weight stepper adds or takes away. The step is the Domain's
    /// text; the locale is passed because the key carries a value (standards §7).
    static func weightStep(_ step: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(step) LB",
                bundle: .module,
                locale: locale,
                comment: "The weight stepper's step, in pounds"
            )
        case .kg:
            String(
                localized: "\(step) KG",
                bundle: .module,
                locale: locale,
                comment: "The weight stepper's step, in kilograms"
            )
        }
    }

    static var repStep: String {
        String(localized: "1 REP", bundle: .module, comment: "The reps stepper's step")
    }

    static var addSet: String {
        String(localized: "+ Add set", bundle: .module, comment: "Button that adds a set to the exercise")
    }

    static var remaining: String {
        String(localized: "REMAINING", bundle: .module, comment: "Heading of the exercises still to come")
    }

    /// "3 × 10": an exercise's sets and reps in the list of those still to come.
    static func scheme(sets: Int, reps: Int, locale: Locale) -> String {
        String(
            localized: "\(sets) × \(reps)",
            bundle: .module,
            locale: locale,
            comment: "An exercise's number of sets, then its reps"
        )
    }

    // MARK: Spoken

    /// "Set 2": how VoiceOver names a set's row.
    static func spokenSet(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Set \(number)",
            bundle: .module,
            locale: locale,
            comment: "Spoken name of a set's row: the set's number, counted from 1"
        )
    }

    static var spokenDropSet: String {
        String(localized: "Drop set", bundle: .module, comment: "Spoken name of a drop set's row")
    }

    /// "185 pounds", "52.5 kilograms": a weight as VoiceOver reads it.
    static func spokenWeight(_ weight: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(localized: "\(weight) pounds", bundle: .module, locale: locale, comment: "Spoken weight, in pounds")
        case .kg:
            String(
                localized: "\(weight) kilograms",
                bundle: .module,
                locale: locale,
                comment: "Spoken weight, in kilograms"
            )
        }
    }

    /// "5 reps", "1 rep".
    static func spokenReps(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) reps",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Spoken number of repetitions"
        )
    }

    /// "Log set 2": the check of a set that is not logged.
    static func logSet(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Log set \(number)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of the button that logs a set: the set's number, counted from 1"
        )
    }

    /// "Undo set 2": the check of a logged set.
    static func undoSet(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Undo set \(number)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of the button that un-logs a set: the set's number, counted from 1"
        )
    }

    static var logDropSet: String {
        String(localized: "Log drop set", bundle: .module, comment: "Spoken label of the button that logs a drop set")
    }

    static var undoDropSet: String {
        String(
            localized: "Undo drop set",
            bundle: .module,
            comment: "Spoken label of the button that un-logs a drop set"
        )
    }

    // MARK: A change that was not saved

    static var couldNotSaveChange: String {
        String(
            localized: "Couldn't save that change",
            bundle: .module,
            comment: "Title of the alert shown when a tap on the workout could not be saved"
        )
    }
}
