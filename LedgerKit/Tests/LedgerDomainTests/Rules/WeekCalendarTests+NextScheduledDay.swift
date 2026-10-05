import Foundation
@testable import LedgerDomain
import Testing

// `WeekCalendar.nextScheduledDay(after:in:)` (F09 S2, criterion 1). Expected days are read off the 2026
// calendar and the schedule of spec §6.4, never taken from the function.

extension WeekCalendarTests {
    /// The calendar of `program`'s block in `zone`.
    static func weeks(
        for program: Program,
        in zone: TimeZone = Fixtures.utc,
        weekStart: Weekday = .monday
    ) -> WeekCalendar {
        var calendar = Fixtures.calendar
        calendar.timeZone = zone
        return WeekCalendar(startDate: program.startDate, weekStart: weekStart, calendar: calendar)
    }

    /// A session of the block that began on Monday 2026-09-14.
    static func session(_ month: Int, _ day: Int, week: Int, _ template: DayTemplateID) -> ScheduledDay {
        ScheduledDay(date: Fixtures.civil(2026, month, day), weekIndex: week, dayTemplateID: template)
    }

    @Test(
        "The next session is the first scheduled day after the moment's own day, up to the block's last week",
        arguments: NextSessionRow.all
    )
    func nextScheduledDay_fourDayBlock_isTheFirstLaterSession(row: NextSessionRow) throws {
        let program = try Fixtures.fourDayProgram()
        let next = Self.weeks(for: program).nextScheduledDay(after: row.after, in: program)
        #expect(next == row.expected)
        #expect(next?.weekday == row.weekday)
    }

    @Test("One instant is a different day far east and far west of UTC, and the next session follows the local day")
    func nextScheduledDay_sameInstant_followsEachZonesDay() throws {
        let program = try Fixtures.fourDayProgram()
        // 2026-09-18 10:30 UTC is Saturday 00:30 on Kiritimati (UTC+14) and Thursday 23:30 in Pago Pago (UTC−11).
        let instant = Fixtures.date(2026, 9, 18, hour: 10, minute: 30)
        let kiritimati = try Self.weeks(for: program, in: Fixtures.zone("Pacific/Kiritimati"))
        let pagoPago = try Self.weeks(for: program, in: Fixtures.zone("Pacific/Pago_Pago"))
        let utc = Self.weeks(for: program)
        #expect(utc.nextScheduledDay(after: instant, in: program) == Self.session(9, 19, week: 0, Fixtures.lowerBDay))
        #expect(kiritimati.nextScheduledDay(after: instant, in: program)
            == Self.session(9, 21, week: 1, Fixtures.upperADay))
        #expect(pagoPago.nextScheduledDay(after: instant, in: program)
            == Self.session(9, 18, week: 0, Fixtures.upperBDay))
    }

    @Test(
        "Around midnight the next session follows the calendar day, on 23- and 25-hour days too (ADR-007)",
        arguments: MidnightRow.all
    )
    func nextScheduledDay_aroundMidnight_followsTheCivilDay(row: MidnightRow) throws {
        let zone = try Fixtures.zone(row.zone)
        let program = try Fixtures.everyDayProgram(startDate: Fixtures.civil(2026, 1, 5), weekCount: 52)
        let start = Self.firstInstant(row.month, row.day, in: zone)
        let end = Self.firstInstant(row.month, row.day + 1, in: zone)
        #expect(end.timeIntervalSince(start) == Double(row.hours) * 3600, "the length of the fixture's day")
        let expected = Fixtures.civil(2026, row.next[0], row.next[1])
        let next = Self.weeks(for: program, in: zone)
            .nextScheduledDay(after: start.addingTimeInterval(row.offset), in: program)
        #expect(next == ScheduledDay(
            date: expected,
            weekIndex: expected.days(since: program.startDate) / 7,
            dayTemplateID: Fixtures.upperADay
        ))
    }

    /// The first instant of a 2026 day in `zone`, from Foundation alone (01:00 where midnight is skipped).
    /// A `day` one past the month's end is the first of the next month.
    static func firstInstant(_ month: Int, _ day: Int, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.startOfDay(for: Fixtures.date(2026, month, day, hour: 12, in: zone))
    }
}

// MARK: - Tables

extension WeekCalendarTests {
    /// A moment (UTC) in spec §6.4's block begun on Monday 2026-09-14, and the next session after it.
    struct NextSessionRow: Sendable, CustomStringConvertible {
        let after: Date
        let expected: ScheduledDay?
        let weekday: Weekday?
        let description: String

        /// `after` is year, month, day, hour, minute; `next` is month and day in 2026.
        init(
            _ description: String,
            after: [Int],
            next: [Int] = [],
            week: Int = 0,
            _ weekday: Weekday? = nil,
            _ template: DayTemplateID? = nil
        ) {
            self.description = description
            self.after = Fixtures.date(after[0], after[1], after[2], hour: after[3], minute: after[4])
            self.weekday = weekday
            expected = template.map { WeekCalendarTests.session(next[0], next[1], week: week, $0) }
        }

        static let all: [NextSessionRow] = inTheBlock + atItsEdges

        static let inTheBlock: [NextSessionRow] = [
            NextSessionRow(
                "Wednesday of week 1: Friday, Upper B (the brief)",
                after: [2026, 9, 16, 12, 0], next: [9, 18], week: 0, .friday, Fixtures.upperBDay
            ),
            NextSessionRow(
                "Saturday of week 1: Monday of week 2, Upper A (the brief)",
                after: [2026, 9, 19, 12, 0], next: [9, 21], week: 1, .monday, Fixtures.upperADay
            ),
            NextSessionRow(
                "the block's first instant, a training day itself: Wednesday, never today",
                after: [2026, 9, 14, 0, 0], next: [9, 16], week: 0, .wednesday, Fixtures.lowerADay
            ),
            NextSessionRow(
                "a rest Tuesday: Wednesday, Lower A",
                after: [2026, 9, 15, 7, 30], next: [9, 16], week: 0, .wednesday, Fixtures.lowerADay
            ),
            NextSessionRow(
                "Friday: Saturday, Lower B, the day after",
                after: [2026, 9, 18, 18, 0], next: [9, 19], week: 0, .saturday, Fixtures.lowerBDay
            ),
            NextSessionRow(
                "the last minute of week 1: Monday of week 2",
                after: [2026, 9, 20, 23, 59], next: [9, 21], week: 1, .monday, Fixtures.upperADay
            ),
            NextSessionRow(
                "the last day of week 7: Monday of the deload week",
                after: [2026, 11, 1, 12, 0], next: [11, 2], week: 7, .monday, Fixtures.upperADay
            ),
            NextSessionRow(
                "Wednesday of the deload week: its Friday",
                after: [2026, 11, 4, 12, 0], next: [11, 6], week: 7, .friday, Fixtures.upperBDay
            )
        ]

        static let atItsEdges: [NextSessionRow] = [
            NextSessionRow("week 8's Friday: nothing is left (the brief)", after: [2026, 11, 6, 6, 0]),
            NextSessionRow("week 8's Saturday, which the deload week does not train", after: [2026, 11, 7, 12, 0]),
            NextSessionRow("the last minute of the block", after: [2026, 11, 8, 23, 59]),
            NextSessionRow("the day after the block", after: [2026, 11, 9, 0, 0]),
            NextSessionRow("months after the block", after: [2027, 3, 1, 12, 0]),
            NextSessionRow(
                "the minute before the block begins: its first session",
                after: [2026, 9, 13, 23, 59], next: [9, 14], week: 0, .monday, Fixtures.upperADay
            ),
            NextSessionRow(
                "weeks before the block: its first session",
                after: [2026, 8, 1, 12, 0], next: [9, 14], week: 0, .monday, Fixtures.upperADay
            ),
            NextSessionRow(
                "a year before the block: its first session",
                after: [2025, 9, 14, 12, 0], next: [9, 14], week: 0, .monday, Fixtures.upperADay
            )
        ]
    }

    /// A moment `offset` seconds after the first instant of a 2026 day in `zone`, in a block that trains
    /// every day: the next session is the day after the moment's own calendar day. `hours` is how long
    /// the day lasts there; a fixture day that is not that long means the zone's rules changed.
    struct MidnightRow: Sendable, CustomStringConvertible {
        let zone: String
        let month: Int
        let day: Int
        let hours: Int
        let offset: TimeInterval
        let next: [Int]
        let description: String

        init(_ zone: String, _ day: [Int], hours: Int = 24, offset: TimeInterval, next: [Int], _ note: String) {
            self.zone = zone
            month = day[0]
            self.day = day[1]
            self.hours = hours
            self.offset = offset
            self.next = next
            description = "\(zone): \(note)"
        }

        static let all: [MidnightRow] = wholeDays + shortDays + longDays

        static let wholeDays: [MidnightRow] = [
            MidnightRow("UTC", [9, 18], offset: -1, next: [9, 18], "Thursday 23:59:59, then Friday"),
            MidnightRow("UTC", [9, 18], offset: 0, next: [9, 19], "Friday 00:00:00, then Saturday"),
            MidnightRow("Pacific/Kiritimati", [9, 18], offset: -1, next: [9, 18], "UTC+14, Thursday 23:59:59"),
            MidnightRow("Pacific/Kiritimati", [9, 18], offset: 0, next: [9, 19], "UTC+14, Friday 00:00:00"),
            MidnightRow("Pacific/Pago_Pago", [9, 18], offset: -1, next: [9, 18], "UTC−11, Thursday 23:59:59"),
            MidnightRow("Pacific/Pago_Pago", [9, 18], offset: 0, next: [9, 19], "UTC−11, Friday 00:00:00")
        ]

        /// Days whose midnight DST skips: they start at 01:00 and last 23 hours.
        static let shortDays: [MidnightRow] = [
            MidnightRow(
                "America/Santiago", [9, 6], hours: 23, offset: -1800, next: [9, 6],
                "Saturday 23:30, 24 hours before Monday 00:30: Sunday is next"
            ),
            MidnightRow(
                "America/Santiago", [9, 6], hours: 23, offset: -1, next: [9, 6],
                "Saturday 23:59:59, before a Sunday with no midnight"
            ),
            MidnightRow(
                "America/Santiago", [9, 6], hours: 23, offset: 0, next: [9, 7],
                "Sunday's first instant, 01:00: Monday is next"
            ),
            MidnightRow(
                "America/Santiago", [9, 6], hours: 23, offset: 23 * 3600 - 1, next: [9, 7],
                "the last second of the 23-hour Sunday"
            ),
            MidnightRow(
                "America/Santiago", [9, 6], hours: 23, offset: 23 * 3600, next: [9, 8],
                "Monday 00:00:00, 23 hours after Sunday began"
            ),
            MidnightRow("America/Havana", [3, 8], hours: 23, offset: -1, next: [3, 8], "Saturday 23:59:59"),
            MidnightRow("America/Havana", [3, 8], hours: 23, offset: 0, next: [3, 9], "Sunday 01:00:00"),
            MidnightRow("Africa/Cairo", [4, 24], hours: 23, offset: -1, next: [4, 24], "Thursday 23:59:59"),
            MidnightRow("Africa/Cairo", [4, 24], hours: 23, offset: 0, next: [4, 25], "Friday 01:00:00")
        ]

        /// Days in which DST repeats the hour at midnight: they last 25 hours.
        static let longDays: [MidnightRow] = [
            MidnightRow(
                "America/Santiago", [4, 4], hours: 25, offset: 600, next: [4, 5],
                "Saturday 00:10, 24 hours before the same Saturday's second 23:10"
            ),
            MidnightRow(
                "America/Santiago", [4, 4], hours: 25, offset: 24 * 3600 + 600, next: [4, 5],
                "Saturday's second 23:10: still Saturday"
            ),
            MidnightRow(
                "America/Santiago", [4, 4], hours: 25, offset: 25 * 3600, next: [4, 6],
                "Sunday 00:00:00, 25 hours after Saturday began"
            ),
            MidnightRow(
                "America/Havana", [11, 1], hours: 25, offset: -1, next: [11, 1],
                "Saturday 23:59:59, before the 25-hour Sunday"
            ),
            MidnightRow(
                "America/Havana", [11, 1], hours: 25, offset: 900, next: [11, 2],
                "Sunday's first 00:15"
            ),
            MidnightRow(
                "America/Havana", [11, 1], hours: 25, offset: 4500, next: [11, 2],
                "Sunday's second 00:15, an hour later"
            ),
            MidnightRow(
                "America/Havana", [11, 1], hours: 25, offset: 25 * 3600 - 1, next: [11, 2],
                "the last second of the 25-hour Sunday"
            ),
            MidnightRow(
                "Africa/Cairo", [10, 29], hours: 25, offset: 24 * 3600 + 1800, next: [10, 30],
                "Thursday's second 23:30"
            )
        ]
    }
}
