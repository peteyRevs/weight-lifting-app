import Foundation
import LedgerDomain

/// The History list as words (F13 S1, criterion 1 as F13 question 6 builds it, A): the Domain groups the workouts
/// into the lifter's stats weeks (`HistoryWeeks`), and this writes each week's header and each workout's row, as
/// Today's RECENT writes one. It sorts nothing itself: the weeks and the rows keep `historyEntries()`'s order,
/// newest first. Every text comes from `HistoryCopy`; a name is data, a volume the Domain's `formatted(in:)` and
/// `spoken(in:locale:)`, and a date `Date.FormatStyle`'s in the injected locale, calendar and time zone.
nonisolated enum HistoryPresentation {
    static let separator = " · "
    /// Between the parts of a row's spoken value.
    static let spokenSeparator = ", "

    static func make(_ input: HistoryInput) -> HistoryModel {
        let weeks = HistoryWeeks.group(input.entries, weekStart: input.weekStart, calendar: input.calendar)
        guard !weeks.isEmpty else {
            return HistoryModel(title: HistoryCopy.title, content: .empty(HistoryModel.Empty(
                title: HistoryCopy.noWorkoutsYet,
                body: HistoryCopy.noWorkoutsBody,
                actionTitle: HistoryCopy.goToToday,
                route: .today
            )))
        }
        let dates = Dates(input)
        var counted = CountedTexts(locale: input.locale)
        var shown: [HistoryModel.Week] = []
        for week in weeks {
            shown.append(HistoryModel.Week(
                id: week.bounds.lowerBound,
                title: dates.title(of: week),
                rows: week.entries.map { row($0, dates: dates, counted: &counted, input: input) }
            ))
        }
        return HistoryModel(title: HistoryCopy.title, content: .weeks(shown))
    }

    /// "Wed · 58 min · 24,180 lb", spoken "Wednesday, 58 minutes, 24,180 pounds, 1 PR": the weekday the workout
    /// started, its length in whole minutes (rounded down, as Today's RECENT rounds it) and its volume in the
    /// lifter's units, then its records when it holds any.
    static func row(
        _ entry: HistoryEntry,
        dates: Dates,
        counted: inout CountedTexts,
        input: HistoryInput
    ) -> HistoryModel.Row {
        let minutes = counted.minutes(Int(clamping: entry.elapsed.components.seconds / 60))
        let units = input.units
        let badge = entry.prCount > 0 ? counted.records(entry.prCount) : nil
        let meta = [
            dates.shortWeekday(entry.startedAt),
            minutes.drawn,
            HistoryCopy.volume(entry.volume.formatted(in: units), units: units, locale: input.locale)
        ]
        let spoken = [
            dates.weekday(entry.startedAt),
            minutes.spoken,
            entry.volume.spoken(in: units, locale: input.locale),
            badge
        ]
        return HistoryModel.Row(
            id: entry.id,
            name: entry.name,
            meta: meta.joined(separator: separator),
            badge: badge,
            spokenValue: spoken.compactMap(\.self).joined(separator: spokenSeparator),
            route: .workout(entry.id)
        )
    }

    /// The counted texts of one model, each looked up once for each number (N4): a counted lookup costs a catalog
    /// read, and a thousand workouts hold a few dozen lengths and record counts.
    struct CountedTexts {
        let locale: Locale
        private var lengths: [Int: (drawn: String, spoken: String)] = [:]
        private var badges: [Int: String] = [:]

        init(locale: Locale) {
            self.locale = locale
        }

        /// "58 min", spoken "58 minutes".
        mutating func minutes(_ count: Int) -> (drawn: String, spoken: String) {
            if let known = lengths[count] {
                return known
            }
            let texts = (HistoryCopy.minutes(count, locale: locale), HistoryCopy.spokenMinutes(count, locale: locale))
            lengths[count] = texts
            return texts
        }

        /// "1 PR", "3 PRs".
        mutating func records(_ count: Int) -> String {
            if let known = badges[count] {
                return known
            }
            let text = HistoryCopy.records(count, locale: locale)
            badges[count] = text
            return text
        }
    }

    /// The date styles of one model, made once, in the injected locale, calendar and time zone.
    struct Dates {
        private let calendar: Calendar
        private let currentYear: Int
        private let short: Date.FormatStyle
        private let wide: Date.FormatStyle
        private let interval: Date.IntervalFormatStyle

        init(_ input: HistoryInput) {
            calendar = input.calendar
            let style = Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: input.locale,
                calendar: input.calendar,
                timeZone: input.calendar.timeZone
            )
            currentYear = input.calendar.component(.year, from: input.now)
            short = style.weekday(.abbreviated)
            wide = style.weekday(.wide)
            interval = Date.IntervalFormatStyle(
                locale: input.locale,
                calendar: input.calendar,
                timeZone: input.calendar.timeZone
            ).month(.abbreviated).day()
        }

        /// "Wed".
        func shortWeekday(_ date: Date) -> String {
            short.format(date)
        }

        /// "Wednesday".
        func weekday(_ date: Date) -> String {
            wide.format(date)
        }

        /// "Sep 7 – 13" and "Aug 31 – Sep 6" in the current year; "Dec 28, 2025 – Jan 3, 2026" for a week with a
        /// day in another (R7): its first day to its last, which the Domain found by counting days.
        func title(of week: HistoryWeeks.Week) -> String {
            let years = [week.bounds.lowerBound, week.lastDay].map { calendar.component(.year, from: $0) }
            let style = years.allSatisfy { $0 == currentYear } ? interval : interval.year()
            return style.format(week.bounds.lowerBound ..< week.lastDay)
        }
    }
}
