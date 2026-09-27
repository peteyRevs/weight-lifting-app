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

/// Maps dates to program weeks and stats weeks (decisions #15 and #18; ADR-007).
///
/// Program weeks count whole calendar days from the civil `startDate` (week 0 = its first 7 days).
/// Stats weeks (`week(containing:)`, `previousCompleteWeek`, `isoWeekKey`) start on `weekStart`.
/// Every date is first mapped to the civil day it falls on in the calendar's time zone; day
/// arithmetic is then pure `CivilDate` arithmetic, and every boundary is the start of its own
/// civil day (`CivilDate.startOfDay(in:)`), never an earlier instant plus n days. So DST weeks are
/// 7 days of 167 or 169 hours, and a day whose midnight is skipped starts its week at 01:00
/// without moving any other boundary. The calendar is always Gregorian; the passed calendar
/// contributes its time zone only (its `firstWeekday` is replaced by `weekStart`, decision #15's
/// Settings override).
public struct WeekCalendar: Sendable {
    /// Decision #18: the calendar day week 0 starts on.
    public let startDate: CivilDate
    public let weekStart: Weekday
    private let calendar: Calendar

    public init(startDate: CivilDate, weekStart: Weekday, calendar: Calendar) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.firstWeekday = weekStart.calendarWeekday
        gregorian.minimumDaysInFirstWeek = 4
        self.calendar = gregorian
        self.weekStart = weekStart
        self.startDate = startDate
    }

    /// The civil day `date` falls on in this calendar's time zone.
    public func civilDate(of date: Date) -> CivilDate {
        CivilDate(date, in: calendar)
    }

    /// Decision #18: whole weeks from `startDate` to the day of `date` (floored, so dates before
    /// the block are negative). A result ≥ `program.weeks.count` means the block has ended.
    public func weekIndex(for date: Date) -> Int {
        let days = civilDate(of: date).days(since: startDate)
        return days >= 0 ? days / 7 : -((6 - days) / 7)
    }

    /// Decision #18: program week `index` as `[start of its first day, start of the next week's first day)`.
    public func bounds(ofWeek index: Int) -> Range<Date> {
        range(from: startDate.adding(days: 7 * index))
    }

    /// Spec §6.1 `sched[7]`: the ISO weekday of `date` in the calendar's time zone.
    public func weekday(of date: Date) -> Weekday {
        civilDate(of: date).weekday
    }

    /// Decision #15: the first day (on `weekStart`) of the stats week containing `date`. F08 uses
    /// this as a new program's `startDate` (decision #18).
    public func firstDayOfWeek(containing date: Date) -> CivilDate {
        let day = civilDate(of: date)
        return day.adding(days: -((day.weekday.rawValue - weekStart.rawValue + 7) % 7))
    }

    /// Decision #15: the stats week containing `date`, starting on `weekStart`.
    public func week(containing date: Date) -> Range<Date> {
        range(from: firstDayOfWeek(containing: date))
    }

    /// Decision #15: the last full stats week before the one containing `date`
    /// ("lb moved" delta baseline). 2026-09-16 with a Monday start → Sep 7 ..< Sep 14.
    public func previousCompleteWeek(before date: Date) -> Range<Date> {
        range(from: firstDayOfWeek(containing: date).adding(days: -7))
    }

    /// Decision #4 chart key: week-based year and week number, weeks starting on `weekStart`
    /// with ISO 8601's "first week holds 4 days" rule (with a Monday start this is the ISO week).
    public func isoWeekKey(for date: Date) -> WeekKey {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WeekKey(year: parts.yearForWeekOfYear ?? 0, week: parts.weekOfYear ?? 0)
    }

    /// The seven civil days from `first`, as start-of-day instants.
    private func range(from first: CivilDate) -> Range<Date> {
        first.startOfDay(in: calendar) ..< first.adding(days: 7).startOfDay(in: calendar)
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
