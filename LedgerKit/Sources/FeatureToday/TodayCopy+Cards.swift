import Foundation
import SwiftUI

/// The texts of Today's five cards and of the off-schedule sheet (`TodayCopy`; standards §7).
nonisolated extension TodayCopy {
    // MARK: Up next

    static var upNext: String {
        String(localized: "UP NEXT", bundle: .module, comment: "Eyebrow of the card for today's session")
    }

    /// "Week 1 of 8": the program week, counted from 1, and the block's length.
    static func week(_ number: Int, of total: Int, locale: Locale) -> String {
        String(
            localized: "Week \(number) of \(total)",
            bundle: .module,
            locale: locale,
            comment: "The program week, counted from 1, then the number of weeks in the block"
        )
    }

    static var deload: String {
        String(localized: "Deload", bundle: .module, comment: "Marks a deload week, after the week's number")
    }

    /// "~38 min": how long a session is expected to take.
    static func estimate(minutes: Int, locale: Locale) -> String {
        String(
            localized: "~\(minutes) min",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "A session's estimated length"
        )
    }

    /// "5 × 5 @ 250": sets, reps and the load, which the caller formats in the lifter's units.
    static func scheme(sets: Int, reps: Int, load: String, locale: Locale) -> String {
        String(
            localized: "\(sets) × \(reps) @ \(load)",
            bundle: .module,
            locale: locale,
            comment: "An exercise's sets, then its reps, then its load, which carries no unit"
        )
    }

    static var startWorkout: String {
        String(localized: "Start workout", bundle: .module)
    }

    /// "Resume · 3:00": the button of a live workout, with the time since it started.
    static func resume(_ elapsed: String, locale: Locale) -> String {
        String(localized: "Resume · \(elapsed)", bundle: .module, locale: locale)
    }

    /// What VoiceOver reads for that button: no time, so the line is true however long ago the model was made.
    static var resumeWorkout: String {
        String(localized: "Resume workout", bundle: .module, comment: "Spoken label of the button of a live workout")
    }

    /// The same line as the button draws it, counting on by the wall clock from the workout's start, so the
    /// model is not rebuilt each second. `pause` freezes it at that moment, for previews and tests; nil counts.
    /// The key is `resume(_:locale:)`'s.
    static func resume(since start: Date, pausedAt pause: Date?) -> Text {
        Text(
            "Resume · \(timerInterval: start ... .distantFuture, pauseTime: pause, countsDown: false)",
            bundle: .module
        )
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
        String(
            localized: "\(done) of \(total) sets",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "The sets done in a workout, then all its sets"
        )
    }

    static var viewSession: String {
        String(localized: "View session", bundle: .module)
    }

    /// "Next: Friday · UB": the next session's weekday and its day's tag.
    static func next(_ weekday: String, tag: String, locale: Locale) -> String {
        String(
            localized: "Next: \(weekday) · \(tag)",
            bundle: .module,
            locale: locale,
            comment: "The next session's weekday, then the short tag of its day, as in UB"
        )
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

    /// "Your block starts on Monday, September 28.": the card's whole body on a day before the block begins.
    static func blockStarts(on date: String, locale: Locale) -> String {
        String(
            localized: "Your block starts on \(date).",
            bundle: .module,
            locale: locale,
            comment: "The rest-day card before a block begins: the block's first day, as in Monday, September 28"
        )
    }

    /// The next session is on one of the seven days the week strip shows. `today` and `next` are weekdays' names.
    static func restNextUp(_ today: String, week: Int, next: String, locale: Locale) -> String {
        String(
            localized: "Nothing scheduled for \(today) in week \(week). Next up is \(next).",
            bundle: .module,
            locale: locale,
            comment: "Today's weekday, the program week counted from 1, then the next session's weekday"
        )
    }

    /// The next session is on a later day than the week strip shows.
    static func restNextUpLater(_ today: String, week: Int, next: String, locale: Locale) -> String {
        String(
            localized: "Nothing scheduled for \(today) in week \(week). Next up is next \(next).",
            bundle: .module,
            locale: locale,
            comment: "Today's weekday, the program week counted from 1, then the next session's weekday"
        )
    }

    /// The block has no later session, and this is its last week.
    static func restLastWeek(_ today: String, week: Int, locale: Locale) -> String {
        String(
            localized: "Nothing scheduled for \(today) in week \(week). This is the last week of the block.",
            bundle: .module,
            locale: locale,
            comment: "Today's weekday, then the program week counted from 1"
        )
    }

    /// The block has no later session, in a week before its last: the weeks after this one are empty.
    static func restNoneLeft(_ today: String, week: Int, locale: Locale) -> String {
        String(
            localized: "Nothing scheduled for \(today) in week \(week). No sessions are left in this block.",
            bundle: .module,
            locale: locale,
            comment: "Today's weekday, then the program week counted from 1"
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
        String(localized: "\(count) exercises", bundle: .module, locale: locale.forCountedText)
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
            locale: locale.forCountedText,
            comment: "Program is the name of the app's Program tab"
        )
    }

    static var openProgram: String {
        String(localized: "Open Program", bundle: .module, comment: "Button that opens the app's Program tab")
    }
}
