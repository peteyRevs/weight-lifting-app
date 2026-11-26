import Foundation
import LedgerDomain

/// The words of the screen before a workout (spec §4.3 "Watch — before workout", §9).
nonisolated extension WatchWorkoutCopy {
    /// "WEEK 1 OF 8".
    static func week(_ number: Int, of count: Int, locale: Locale) -> String {
        String(
            localized: "WEEK \(number) OF \(count)",
            bundle: .module,
            locale: locale,
            comment: "Eyebrow before a workout: the program week, counted from 1, then the weeks of the block"
        )
    }

    /// "WEEK 8 OF 8 · DELOAD".
    static func deloadWeek(_ number: Int, of count: Int, locale: Locale) -> String {
        String(
            localized: "WEEK \(number) OF \(count) · DELOAD",
            bundle: .module,
            locale: locale,
            comment: "Eyebrow before a workout in a lighter week: the program week, then the weeks of the block"
        )
    }

    static var restDay: String {
        String(localized: "Rest day", bundle: .module, comment: "Title before a workout on a day with no session")
    }

    static var nothingScheduled: String {
        String(localized: "Nothing scheduled today.", bundle: .module, comment: "Line under the title on a rest day")
    }

    /// The first fragment of "Logged · 18 sets · 24,180 lb".
    static var logged: String {
        String(localized: "Logged", bundle: .module, comment: "Marks today's session as already trained")
    }

    static var loggedEarlierToday: String {
        String(
            localized: "Logged earlier today",
            bundle: .module,
            comment: "Line under the day's name when today's session was trained earlier, on either device"
        )
    }

    /// "18 sets".
    static func sets(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) sets",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "A number of sets, in the line under the day's name"
        )
    }

    /// "5 exercises".
    static func exercises(_ count: Int, locale: Locale) -> String {
        String(
            localized: "\(count) exercises",
            bundle: .module,
            locale: locale.forCountedText,
            comment: "The number of exercises of today's session"
        )
    }

    /// "Bench Press first".
    static func first(_ exercise: String, locale: Locale) -> String {
        String(
            localized: "\(exercise) first",
            bundle: .module,
            locale: locale,
            comment: "The exercise today's session opens with"
        )
    }

    static var emptyDay: String {
        String(localized: "empty day", bundle: .module, comment: "Ends the line of a session that has no exercise")
    }

    /// "24,180 lb": a volume, or a weight, in the lifter's unit.
    static func weight(_ number: String, units: Units, locale: Locale) -> String {
        switch units {
        case .lb: String(localized: "\(number) lb", bundle: .module, locale: locale, comment: "A weight in pounds")
        case .kg: String(localized: "\(number) kg", bundle: .module, locale: locale, comment: "A weight in kilograms")
        }
    }

    static var start: String {
        String(localized: "Start", bundle: .module, comment: "Button that starts today's session")
    }

    /// "Next: Friday · UB".
    static func next(_ weekday: String, tag: String, locale: Locale) -> String {
        String(
            localized: "Next: \(weekday) · \(tag)",
            bundle: .module,
            locale: locale,
            comment: "The next session this program week: its weekday, then its day's short tag"
        )
    }

    /// "Next: week 2".
    static func nextWeek(_ number: Int, locale: Locale) -> String {
        String(
            localized: "Next: week \(number)",
            bundle: .module,
            locale: locale,
            comment: "The program week, counted from 1, that holds the next session"
        )
    }

    static var noProgram: String {
        String(localized: "No program on watch", bundle: .module, comment: "Title before a workout with no program")
    }

    /// "Open Ledger on iPhone": `app` is the app's display name, never a literal (product decisions › Naming).
    static func openOnIPhone(_ app: String, locale: Locale) -> String {
        String(
            localized: "Open \(app) on iPhone",
            bundle: .module,
            locale: locale,
            comment: "Asks the lifter to open the app, named first, on the iPhone, which sends the program"
        )
    }
}
