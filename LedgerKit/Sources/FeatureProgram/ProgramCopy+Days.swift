import Foundation

/// The texts of the builder's training days and of its notices (`ProgramCopy`; standards §7).
nonisolated extension ProgramCopy {
    // MARK: Training days

    static var trainingDays: String {
        String(localized: "TRAINING DAYS", bundle: .module, comment: "Eyebrow of the list of training days")
    }

    /// "58 sets a week": every day's sets together, after the number of days.
    static func setsAWeek(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) sets a week",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "Every training day's sets together, after the number of training days"
        )
    }

    static var sharedByEveryWeek: String {
        String(
            localized: "Shared by every week. The schedule above decides which day you train, and when.",
            bundle: .module
        )
    }

    static func exercises(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) exercises",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "On a day's card: the number of exercises the day has"
        )
    }

    static func sets(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) sets",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "On a day's card: the day's sets, its drop sets among them"
        )
    }

    /// "~39 min": how long a day is expected to take.
    static func estimate(minutes: Int, locale: Locale) -> String {
        String(
            localized: "~\(minutes) min",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "A day's estimated length"
        )
    }

    static var noExercisesYet: String {
        String(localized: "No exercises yet", bundle: .module)
    }

    /// "+2": the exercises of a day after the four its card names.
    static func more(_ count: Int, locale: Locale) -> String {
        String(
            localized: "+\(count)",
            bundle: .module,
            locale: locale,
            comment: "On a day's card: how many more exercises the day has than the card names"
        )
    }

    static var unknownExercise: String {
        String(localized: "—", bundle: .module, comment: "Stands for the name of an exercise that is not stored")
    }

    static var addTrainingDay: String {
        String(localized: "+ Add training day", bundle: .module)
    }

    static var newDay: String {
        String(localized: "New day", bundle: .module, comment: "The name a training day is given when it is added")
    }

    // MARK: Notices

    static var minimumTwoWeeks: String {
        String(localized: "A block needs at least 2 weeks.", bundle: .module)
    }

    /// "Week 8 has logged sessions and can't be removed."
    static func weekHasLoggedSessions(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Week \(number) has logged sessions and can't be removed.",
            bundle: .module,
            locale: locale,
            comment: "Shown when the last week cannot be removed: the week's number, counted from 1"
        )
    }

    static var dayHasNoExercises: String {
        String(localized: "Add at least one exercise before scheduling this day.", bundle: .module)
    }
}
