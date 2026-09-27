import Foundation

/// A calendar week key, `year` being the week-based year (ISO 8601 style: the week that holds
/// the year's fourth day is week 1).
public struct WeekKey: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let week: Int

    public init(year: Int, week: Int) {
        self.year = year
        self.week = week
    }

    public static func < (lhs: WeekKey, rhs: WeekKey) -> Bool {
        (lhs.year, lhs.week) < (rhs.year, rhs.week)
    }
}

/// Maps dates to program weeks and stats weeks (decisions #15 and #18).
///
/// Program weeks count whole calendar days from `startDate` (week 0 = its first 7 days).
/// Stats weeks (`week(containing:)`, `previousCompleteWeek`, `isoWeekKey`) start on `weekStart`.
/// All arithmetic is in calendar days in the given calendar's time zone, so DST weeks are
/// 7 days long even when they are 167 or 169 hours. The calendar is always Gregorian; the
/// passed calendar contributes its time zone only (its `firstWeekday` is replaced by
/// `weekStart`, decision #15's Settings override).
public struct WeekCalendar: Sendable {
    /// The start of the day of the program's `startDate`, in the calendar's time zone.
    public let startDate: Date
    public let weekStart: Weekday
    private let calendar: Calendar

    public init(startDate: Date, weekStart: Weekday, calendar: Calendar) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.firstWeekday = weekStart.calendarWeekday
        gregorian.minimumDaysInFirstWeek = 4
        self.calendar = gregorian
        self.weekStart = weekStart
        self.startDate = gregorian.startOfDay(for: startDate)
    }

    /// Decision #18: whole weeks since `startDate` (floored, so dates before it are negative).
    /// A result ≥ `program.weeks.count` means the block has ended.
    public func weekIndex(for date: Date) -> Int {
        let days = calendar.dateComponents([.day], from: startDate, to: calendar.startOfDay(for: date)).day ?? 0
        return days >= 0 ? days / 7 : -((6 - days) / 7)
    }

    /// Decision #18: program week `index` as `[first day 00:00, first day + 7 days 00:00)`.
    public func bounds(ofWeek index: Int) -> Range<Date> {
        let lower = adding(days: 7 * index, to: startDate)
        return lower ..< adding(days: 7, to: lower)
    }

    /// Spec §6.1 `sched[7]`: the ISO weekday of `date` in the calendar's time zone.
    public func weekday(of date: Date) -> Weekday {
        Weekday(calendarWeekday: calendar.component(.weekday, from: date)) ?? .monday
    }

    /// Decision #15: the stats week containing `date`, starting on `weekStart`.
    public func week(containing date: Date) -> Range<Date> {
        let offset = (weekday(of: date).rawValue - weekStart.rawValue + 7) % 7
        let lower = adding(days: -offset, to: calendar.startOfDay(for: date))
        return lower ..< adding(days: 7, to: lower)
    }

    /// Decision #15: the last full stats week before the one containing `date`
    /// ("lb moved" delta baseline). 2026-09-16 with a Monday start → Sep 7 ..< Sep 14.
    public func previousCompleteWeek(before date: Date) -> Range<Date> {
        let current = week(containing: date).lowerBound
        return adding(days: -7, to: current) ..< current
    }

    /// Decision #4 chart key: week-based year and week number, weeks starting on `weekStart`
    /// with ISO 8601's "first week holds 4 days" rule (with a Monday start this is the ISO week).
    public func isoWeekKey(for date: Date) -> WeekKey {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WeekKey(year: parts.yearForWeekOfYear ?? 0, week: parts.weekOfYear ?? 0)
    }

    private func adding(days: Int, to date: Date) -> Date {
        // Gregorian day arithmetic cannot fail for representable dates; the fallback is unreachable.
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86400)
    }
}

// MARK: - Schedule helpers (decision #18)

public extension WeekCalendar {
    /// The day template scheduled on `date`, or `nil` when it is a rest day (an off-schedule
    /// day: "Train off-schedule" offers the week's days) or outside the block.
    func scheduledDay(on date: Date, in program: Program) -> DayTemplateID? {
        program.week(at: weekIndex(for: date))?.schedule[weekday(of: date)]
    }

    /// Decision #18: the block has ended once `date` is in week `weeks.count` or later.
    func isBlockComplete(_ program: Program, on date: Date) -> Bool {
        weekIndex(for: date) >= program.weeks.count
    }

    /// Decision #18: program weeks before the one containing `date` (and inside the block) in
    /// which nothing was trained. Pass each finished workout's `source.weekIndex` as `trainedWeeks`;
    /// feed the result to `MissTracking.recordSkippedWeek(_:in:)`.
    func skippedWeeks(before date: Date, trainedWeeks: Set<Int>, weekCount: Int) -> [Int] {
        let end = min(weekIndex(for: date), weekCount)
        return (0 ..< max(0, end)).filter { !trainedWeeks.contains($0) }
    }
}
