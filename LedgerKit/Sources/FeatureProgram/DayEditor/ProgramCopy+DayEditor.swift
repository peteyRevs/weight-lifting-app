import Foundation
import LedgerDomain

/// The texts of the Day editor: its header, the superset headers, an exercise's row and "Delete day"
/// (`ProgramCopy`; standards §7). A load, an RPE and a rest arrive as the Domain formats them; the panel under
/// an open exercise has its texts in `ProgramCopy+SlotEditor.swift`.
nonisolated extension ProgramCopy {
    // MARK: Header

    static var backToProgram: String {
        String(localized: "Program", bundle: .module, comment: "Back button of the Day editor: to the Program screen")
    }

    /// "DAY 1 OF 4".
    static func dayPosition(_ number: Int, of total: Int, locale: Locale) -> String {
        String(
            localized: "DAY \(number) OF \(total)",
            bundle: .module,
            locale: locale,
            comment: "Eyebrow of the Day editor: the day's place among the program's days, then how many there are"
        )
    }

    static var done: String {
        String(localized: "Done", bundle: .module, comment: "Button that leaves the Day editor")
    }

    static var dayName: String {
        String(
            localized: "Day name",
            bundle: .module,
            comment: "Placeholder and spoken label of the field that holds a training day's name"
        )
    }

    // MARK: Superset header

    static var supersetMark: String {
        String(localized: "SUPERSET", bundle: .module, comment: "Eyebrow above exercises done back to back")
    }

    static var supersetSpoken: String {
        String(localized: "Superset", bundle: .module, comment: "Spoken heading above exercises done back to back")
    }

    /// "2 exercises back to back".
    static func backToBack(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) exercises back to back",
            bundle: .module,
            locale: locale,
            comment: "Under SUPERSET: how many exercises the superset has"
        )
    }

    /// "rest after B".
    static func restAfter(_ letter: String, locale: Locale) -> String {
        String(
            localized: "rest after \(letter)",
            bundle: .module,
            locale: locale,
            comment: "Under SUPERSET: the letter of the superset's last exercise, after which the lifter rests"
        )
    }

    // MARK: An exercise's row

    /// "4A": the number of the exercise's group, then its letter in a superset; "4" with an empty letter.
    static func slotIndex(_ number: Int, letter: String, locale: Locale) -> String {
        String(
            localized: "\(number)\(letter)",
            bundle: .module,
            locale: locale,
            comment: "An exercise's place in its day: its number, then its letter within a superset, as in 4A"
        )
    }

    /// "4A, Lat Pulldown".
    static func spokenRow(index: String, name: String, locale: Locale) -> String {
        String(
            localized: "\(index), \(name)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of an exercise in the Day editor: its place in the day, as in 4A, then its name"
        )
    }

    static func equipment(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: String(localized: "Barbell", bundle: .module)
        case .dumbbell: String(localized: "Dumbbell", bundle: .module)
        case .cable: String(localized: "Cable", bundle: .module)
        case .machine: String(localized: "Machine", bundle: .module)
        case .bodyweight: String(localized: "Bodyweight", bundle: .module)
        case .kettlebell: String(localized: "Kettlebell", bundle: .module)
        case .band: String(localized: "Band", bundle: .module)
        }
    }

    /// "+5/wk": linear progression, with the step it adds each week.
    static func stepAWeek(_ step: String, locale: Locale) -> String {
        String(
            localized: "+\(step)/wk",
            bundle: .module,
            locale: locale,
            comment: "On an exercise's row: the load it adds each week, with no unit"
        )
    }

    /// "Reps 10–12": double progression, with its range.
    static func repRange(_ floor: Int, _ top: Int, locale: Locale) -> String {
        String(
            localized: "Reps \(floor)–\(top)",
            bundle: .module,
            locale: locale,
            comment: "On an exercise's row: the fewest reps of its range, then the most"
        )
    }

    static var fixed: String {
        String(
            localized: "Fixed",
            bundle: .module,
            comment: "A progression that keeps the same load every week: on an exercise's row, and as its choice"
        )
    }

    static var dropMark: String {
        String(localized: "drop", bundle: .module, comment: "On an exercise's row: it ends on a drop set")
    }

    /// "RPE 8.5".
    static func rpe(_ value: String, locale: Locale) -> String {
        String(localized: "RPE \(value)", bundle: .module, locale: locale, comment: "A target RPE, as in RPE 8.5")
    }

    /// "2:30 rest".
    static func restOf(_ length: String, locale: Locale) -> String {
        String(
            localized: "\(length) rest",
            bundle: .module,
            locale: locale,
            comment: "On an exercise's row: the rest after each set, as in 2:30 rest or 45s rest"
        )
    }

    static var noRest: String {
        String(
            localized: "no rest",
            bundle: .module,
            comment: "On the row of an exercise in a superset that is not its last: the next exercise follows at once"
        )
    }

    /// "5×5".
    static func scheme(sets: Int, reps: Int, locale: Locale) -> String {
        String(
            localized: "\(sets)×\(reps)",
            bundle: .module,
            locale: locale,
            comment: "On an exercise's row: its sets, then its reps"
        )
    }

    /// "185 lb", "82.5 kg".
    static func load(_ value: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb: String(localized: "\(value) lb", bundle: .module, locale: locale, comment: "A load in pounds")
        case .kg: String(localized: "\(value) kg", bundle: .module, locale: locale, comment: "A load in kilograms")
        }
    }

    // MARK: The foot

    static var addExerciseFromLibrary: String {
        String(localized: "+ Add exercise from library", bundle: .module)
    }

    static var deleteDay: String {
        String(localized: "Delete day", bundle: .module, comment: "Button at the foot of the Day editor")
    }

    /// "Delete Lower B?".
    static func deleteTitle(_ name: String, locale: Locale) -> String {
        String(
            localized: "Delete \(name)?",
            bundle: .module,
            locale: locale,
            comment: "Title of the confirmation before a training day is deleted: the day's short name"
        )
    }

    /// "It's scheduled in 8 weeks. Those days become rest."
    static func scheduledInWeeks(_ count: Int, locale: Locale) -> String {
        String(
            localized: "It's scheduled in \(count) weeks. Those days become rest.",
            bundle: .module,
            locale: locale,
            comment: "Under the confirmation's title: how many weeks of the block train the day"
        )
    }

    static var delete: String {
        String(localized: "Delete", bundle: .module, comment: "Confirms that a training day is deleted")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module)
    }
}
