import Foundation

/// The texts of Today's five cards and of the off-schedule sheet (`TodayCopy`; standards §7).
nonisolated extension TodayCopy {
    // MARK: Up next

    static var upNext: String {
        String(localized: "UP NEXT", bundle: .module, comment: "Eyebrow of the card for today's session")
    }

    /// "Week 1 of 8": the program week, counted from 1, and the block's length.
    static func week(_ number: Int, of total: Int, locale: Locale) -> String {
        String(localized: "Week \(number) of \(total)", bundle: .module, locale: locale)
    }

    static var deload: String {
        String(localized: "Deload", bundle: .module, comment: "Marks a deload week, after the week's number")
    }

    /// "~38 min": how long a session is expected to take.
    static func estimate(minutes: Int, locale: Locale) -> String {
        String(localized: "~\(minutes) min", bundle: .module, locale: locale, comment: "A session's estimated length")
    }

    /// "5 × 5 @ 250": sets, reps and the load, which the caller formats in the lifter's units.
    static func scheme(sets: Int, reps: Int, load: String, locale: Locale) -> String {
        String(
            localized: "\(sets) × \(reps) @ \(load)",
            bundle: .module,
            locale: locale,
            comment: "An exercise's sets, reps and load; the load carries no unit"
        )
    }

    static var startWorkout: String {
        String(localized: "Start workout", bundle: .module)
    }

    /// "Resume · 3:00": the button of a live workout, with the time since it started.
    static func resume(_ elapsed: String, locale: Locale) -> String {
        String(localized: "Resume · \(elapsed)", bundle: .module, locale: locale)
    }

    // MARK: Logged

    static func loggedWeek(_ number: Int, locale: Locale) -> String {
        String(
            localized: "LOGGED · WEEK \(number)",
            bundle: .module,
            locale: locale,
            comment: "Eyebrow of the card for today's finished session, with the program week"
        )
    }

    /// "15 of 15 sets": the sets done, of the workout's set rows.
    static func sets(done: String, of total: Int, locale: Locale) -> String {
        String(localized: "\(done) of \(total) sets", bundle: .module, locale: locale)
    }

    static var viewSession: String {
        String(localized: "View session", bundle: .module)
    }

    /// "Next: Friday · UB": the next session's weekday and its day's tag.
    static func next(_ weekday: String, tag: String, locale: Locale) -> String {
        String(localized: "Next: \(weekday) · \(tag)", bundle: .module, locale: locale)
    }

    /// "Next: week 2": the next session is in a later program week.
    static func nextWeek(_ number: Int, locale: Locale) -> String {
        String(localized: "Next: week \(number)", bundle: .module, locale: locale)
    }

    // MARK: Rest day

    static var scheduledRest: String {
        String(localized: "SCHEDULED REST", bundle: .module, comment: "Eyebrow of the card for a day with no session")
    }

    static var noSessionToday: String {
        String(localized: "No session today", bundle: .module)
    }

    /// The next session is later in this program week. `today` and `next` are weekdays' names.
    static func restNextUp(_ today: String, week: Int, next: String, locale: Locale) -> String {
        String(
            localized: "Nothing scheduled for \(today) in week \(week). Next up is \(next).",
            bundle: .module,
            locale: locale
        )
    }

    /// The next session is in a later program week.
    static func restNextUpLater(_ today: String, week: Int, next: String, locale: Locale) -> String {
        String(
            localized: "Nothing scheduled for \(today) in week \(week). Next up is next \(next).",
            bundle: .module,
            locale: locale
        )
    }

    /// The block has no later session.
    static func restNothingLeft(_ today: String, week: Int, locale: Locale) -> String {
        String(
            localized: "Nothing scheduled for \(today) in week \(week). This is the last week of the block.",
            bundle: .module,
            locale: locale
        )
    }

    static var editThisWeek: String {
        String(localized: "Edit this week", bundle: .module)
    }

    /// The rest-day card's second button, and the title of the sheet it opens.
    static var trainOffSchedule: String {
        String(localized: "Train off-schedule", bundle: .module)
    }

    // MARK: Off-schedule sheet

    static func pickADay(week: Int, locale: Locale) -> String {
        String(localized: "Pick a day from week \(week).", bundle: .module, locale: locale)
    }

    /// "4 exercises".
    static func exercises(_ count: Int, locale: Locale) -> String {
        String(localized: "\(count) exercises", bundle: .module, locale: locale)
    }

    static var logged: String {
        String(localized: "Logged", bundle: .module, comment: "Marks a day already trained this week")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module)
    }

    // MARK: No program, block complete

    static var noProgramTitle: String {
        String(localized: "No program yet", bundle: .module)
    }

    static var noProgramBody: String {
        String(localized: "Set up a program to see your next session here.", bundle: .module)
    }

    static var setUpProgram: String {
        String(localized: "Set up program", bundle: .module)
    }

    static var blockCompleteTitle: String {
        String(localized: "Block complete", bundle: .module)
    }

    /// "8 weeks done. Start the next block from Program."
    static func blockCompleteBody(weeks: Int, locale: Locale) -> String {
        String(
            localized: "\(weeks) weeks done. Start the next block from Program.",
            bundle: .module,
            locale: locale,
            comment: "Program is the name of the app's Program tab"
        )
    }

    static var openProgram: String {
        String(localized: "Open Program", bundle: .module, comment: "Button that opens the app's Program tab")
    }
}
