import Foundation
import LedgerDomain

/// The texts of the panel under an open exercise: the shown week's prescription, the stepper fields, the
/// progression and its note, the drop set, the slot's actions and the loads of every week (`ProgramCopy`;
/// standards §7). A line that prints a load has one key for each unit.
nonisolated extension ProgramCopy {
    // MARK: The prescription, week by week

    static var heldMark: String {
        String(
            localized: "HELD",
            bundle: .module,
            comment: "Marks a week whose load is held because a set was missed the week before"
        )
    }

    /// "5 × 5 @ 185 lb".
    static func target(sets: Int, reps: Int, load: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "\(sets) × \(reps) @ \(load) lb",
                bundle: .module,
                locale: locale,
                comment: "A week's prescription: sets, then reps, then the load in pounds"
            )
        case .kg:
            String(
                localized: "\(sets) × \(reps) @ \(load) kg",
                bundle: .module,
                locale: locale,
                comment: "A week's prescription: sets, then reps, then the load in kilograms"
            )
        }
    }

    /// "W4 52.5".
    static func stripWeek(_ number: Int, load: String, locale: Locale) -> String {
        String(
            localized: "W\(number) \(load)",
            bundle: .module,
            locale: locale,
            comment: "One week among the loads of every week: W for week and its number, then its load, with no unit"
        )
    }

    /// "W8 240 (deload)".
    static func stripDeloadWeek(_ number: Int, load: String, locale: Locale) -> String {
        String(
            localized: "W\(number) \(load) (deload)",
            bundle: .module,
            locale: locale,
            comment: "A deload week among the loads of every week: the week's number, then its load, with no unit"
        )
    }

    /// "W5 190 (held)".
    static func stripHeldWeek(_ number: Int, load: String, locale: Locale) -> String {
        String(
            localized: "W\(number) \(load) (held)",
            bundle: .module,
            locale: locale,
            comment: "A week whose load is held, among the loads of every week: its number, then its load, with no unit"
        )
    }

    // MARK: The fields

    static var setsLabel: String {
        String(localized: "SETS", bundle: .module, comment: "Label of the stepper for an exercise's sets")
    }

    static var repsLabel: String {
        String(localized: "REPS", bundle: .module, comment: "Label of the stepper for an exercise's reps")
    }

    static var repFloorLabel: String {
        String(localized: "REP FLOOR", bundle: .module, comment: "Label of the stepper for the fewest reps of a range")
    }

    static var topOfRangeLabel: String {
        String(localized: "TOP OF RANGE", bundle: .module, comment: "Label of the stepper for the most reps of a range")
    }

    static var startLoadLabel: String {
        String(localized: "START LOAD", bundle: .module, comment: "Label of the stepper for the load of the first week")
    }

    static var targetRPELabel: String {
        String(localized: "TARGET RPE", bundle: .module, comment: "Label of the stepper for an exercise's target RPE")
    }

    static var setsSpoken: String {
        String(localized: "Sets", bundle: .module, comment: "Spoken label of the stepper for an exercise's sets")
    }

    static var repsSpoken: String {
        String(localized: "Reps", bundle: .module, comment: "Spoken label of the stepper for an exercise's reps")
    }

    static var repFloorSpoken: String {
        String(
            localized: "Rep floor",
            bundle: .module,
            comment: "Spoken label of the stepper for the fewest reps of a range"
        )
    }

    static var topOfRangeSpoken: String {
        String(
            localized: "Top of range",
            bundle: .module,
            comment: "Spoken label of the stepper for the most reps of a range"
        )
    }

    static var startLoadSpoken: String {
        String(
            localized: "Start load",
            bundle: .module,
            comment: "Spoken label of the stepper for the load of the first week"
        )
    }

    static var targetRPESpoken: String {
        String(
            localized: "Target RPE",
            bundle: .module,
            comment: "Spoken label of the stepper for an exercise's target RPE"
        )
    }

    // MARK: Progression

    static var progressionTitle: String {
        String(localized: "PROGRESSION", bundle: .module, comment: "Eyebrow of the choice of a progression")
    }

    static func progression(_ progression: Progression) -> String {
        switch progression {
        case .linear: String(localized: "Linear", bundle: .module, comment: "A progression: more load each week")
        case .double: String(localized: "Double", bundle: .module, comment: "A progression: more reps, then more load")
        case .fixed: fixed
        }
    }

    /// "Adds 5 lb a week from 180 lb. A week with a missed set holds the load."
    static func linearNote(step: String, start: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "Adds \(step) lb a week from \(start) lb. A week with a missed set holds the load.",
                bundle: .module,
                locale: locale,
                comment: "Linear progression: the pounds added each week, then the first week's load in pounds"
            )
        case .kg:
            String(
                localized: "Adds \(step) kg a week from \(start) kg. A week with a missed set holds the load.",
                bundle: .module,
                locale: locale,
                comment: "Linear progression: the kilograms added each week, then the first week's load in kilograms"
            )
        }
    }

    /// "Adds a rep each week up to 12, then +2.5 lb back at 10."
    static func doubleNote(top: Int, step: String, floor: Int, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "Adds a rep each week up to \(top), then +\(step) lb back at \(floor).",
                bundle: .module,
                locale: locale,
                comment: "Double progression: the most reps of the range, the pounds then added, the fewest reps"
            )
        case .kg:
            String(
                localized: "Adds a rep each week up to \(top), then +\(step) kg back at \(floor).",
                bundle: .module,
                locale: locale,
                comment: "Double progression: the most reps of the range, the kilograms then added, the fewest reps"
            )
        }
    }

    /// "Stays at 160 lb for the whole block."
    static func fixedNote(start: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb:
            String(
                localized: "Stays at \(start) lb for the whole block.",
                bundle: .module,
                locale: locale,
                comment: "Fixed progression: the load of every week, in pounds"
            )
        case .kg:
            String(
                localized: "Stays at \(start) kg for the whole block.",
                bundle: .module,
                locale: locale,
                comment: "Fixed progression: the load of every week, in kilograms"
            )
        }
    }

    // MARK: Drop set and the slot's actions

    static var dropSet: String {
        String(localized: "Drop set", bundle: .module, comment: "Switch that adds a drop set to an exercise")
    }

    static var dropSetNoteOff: String {
        String(localized: "One extra set at −15% after the last working set.", bundle: .module)
    }

    static var dropSetNoteOn: String {
        String(localized: "One extra set at −15%, straight after the last working set.", bundle: .module)
    }

    static var breakOut: String {
        String(localized: "Break out", bundle: .module, comment: "Button that takes an exercise out of its superset")
    }

    static var supersetWithNext: String {
        String(localized: "Superset with next", bundle: .module)
    }

    static var moveUp: String {
        String(localized: "Move up", bundle: .module)
    }

    static var moveDown: String {
        String(localized: "Move down", bundle: .module)
    }

    static var remove: String {
        String(localized: "Remove", bundle: .module, comment: "Button that removes an exercise from its day")
    }
}
