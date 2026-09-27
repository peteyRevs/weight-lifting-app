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
/// arithmetic is then pure integer day-number arithmetic, and every boundary is the start of its
/// own civil day (`CivilDate.startOfDay`), never an earlier instant plus n days. So DST weeks are
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

    /// The civil day `date` falls on in this calendar's time zone, or `nil` outside 0001…9999.
    public func civilDate(of date: Date) -> CivilDate? {
        CivilDate(date, in: calendar)
    }

    /// Decision #18: whole weeks from `startDate` to the day of `date` (floored, so dates before
    /// the block are negative). A result ≥ `program.weeks.count` means the block has ended.
    public func weekIndex(for date: Date) -> Int {
        let days = dayNumber(of: date) - startDate.daysSinceEpoch
        return days >= 0 ? days / 7 : -((6 - days) / 7)
    }

    /// Decision #18: program week `index` as `[start of its first day, start of the next week's first day)`.
    /// Days before 0001-01-01 or after 9999-12-31 (and indices that overflow `Int`) are clamped to
    /// those edges, so an absurd index yields an empty range there instead of trapping.
    public func bounds(ofWeek index: Int) -> Range<Date> {
        let (offset, multiplyOverflow) = index.multipliedReportingOverflow(by: 7)
        let (first, addOverflow) = startDate.daysSinceEpoch.addingReportingOverflow(offset)
        guard !multiplyOverflow, !addOverflow else {
            return range(fromDay: index < 0 ? Int.min : Int.max)
        }
        return range(fromDay: first)
    }

    /// Spec §6.1 `sched[7]`: the ISO weekday of `date` in the calendar's time zone.
    public func weekday(of date: Date) -> Weekday {
        CivilDate.weekday(ofDayNumber: dayNumber(of: date))
    }

    /// Decision #15: the first day (on `weekStart`) of the stats week containing `date`, or `nil`
    /// when that day is outside 0001…9999. F08 uses this as a new program's `startDate` (decision #18).
    public func firstDayOfWeek(containing date: Date) -> CivilDate? {
        CivilDate(daysSinceEpoch: firstDayNumber(ofWeekContaining: date))
    }

    /// Decision #15: the stats week containing `date`, starting on `weekStart`.
    public func week(containing date: Date) -> Range<Date> {
        range(fromDay: firstDayNumber(ofWeekContaining: date))
    }

    /// Decision #15: the last full stats week before the one containing `date`
    /// ("lb moved" delta baseline). 2026-09-16 with a Monday start → Sep 7 ..< Sep 14.
    public func previousCompleteWeek(before date: Date) -> Range<Date> {
        range(fromDay: firstDayNumber(ofWeekContaining: date) - 7)
    }

    /// Decision #4 chart key: week-based year and week number, weeks starting on `weekStart`
    /// with ISO 8601's "first week holds 4 days" rule (with a Monday start this is the ISO week).
    public func isoWeekKey(for date: Date) -> WeekKey {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WeekKey(year: parts.yearForWeekOfYear ?? 0, week: parts.weekOfYear ?? 0)
    }

    // Day numbers (days since 1970-01-01) are plain `Int`s here, unbounded by `CivilDate`'s
    // 0001…9999 range, so the non-optional range API stays total.

    private func dayNumber(of date: Date) -> Int {
        CivilDate.dayNumber(of: date, in: calendar)
    }

    private func firstDayNumber(ofWeekContaining date: Date) -> Int {
        let day = dayNumber(of: date)
        return day - (CivilDate.weekday(ofDayNumber: day).rawValue - weekStart.rawValue + 7) % 7
    }

    /// The seven civil days from day number `first`, as start-of-day instants (saturating at the
    /// clamped edges; `CivilDate.startOfDay(dayNumber:in:)` is monotonic, so the range never inverts).
    private func range(fromDay first: Int) -> Range<Date> {
        let last = first > Int.max - 7 ? Int.max : first + 7
        return CivilDate.startOfDay(dayNumber: first, in: calendar) ..< CivilDate.startOfDay(
            dayNumber: last,
            in: calendar
        )
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
