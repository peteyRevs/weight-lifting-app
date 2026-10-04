import Foundation
@testable import LedgerDomain
import Testing

/// `ProgramTemplates.startDate`: decision #18's date, the first day of the week the lifter starts in (the data
/// half of F08 criteria 4 and 11).
@Suite("ProgramTemplates · start date", .tags(.domain))
struct ProgramTemplatesStartDateTests {
    struct Row: Sendable, CustomStringConvertible {
        let zone: String
        let weekStart: Weekday
        /// Local year, month, day, hour, minute.
        let now: [Int]
        /// Year, month, day.
        let expected: [Int]

        var description: String {
            "\(zone) \(now), weeks start on \(weekStart): \(expected)"
        }
    }

    static let rows: [Row] = [
        // Criterion 11: Wednesday 2026-09-16, weeks starting on Monday.
        Row(zone: "UTC", weekStart: .monday, now: [2026, 9, 16, 5, 20], expected: [2026, 9, 14]),
        Row(zone: "UTC", weekStart: .sunday, now: [2026, 9, 16, 5, 20], expected: [2026, 9, 13]),
        Row(zone: "UTC", weekStart: .saturday, now: [2026, 9, 16, 5, 20], expected: [2026, 9, 12]),
        Row(zone: "UTC", weekStart: .wednesday, now: [2026, 9, 16, 5, 20], expected: [2026, 9, 16]),
        Row(zone: "UTC", weekStart: .thursday, now: [2026, 9, 16, 5, 20], expected: [2026, 9, 10]),
        // The week's first and last minute.
        Row(zone: "UTC", weekStart: .monday, now: [2026, 9, 14, 0, 0], expected: [2026, 9, 14]),
        Row(zone: "UTC", weekStart: .monday, now: [2026, 9, 20, 23, 59], expected: [2026, 9, 14]),
        Row(zone: "UTC", weekStart: .monday, now: [2026, 9, 21, 0, 0], expected: [2026, 9, 21]),
        // A week that starts in the year before.
        Row(zone: "UTC", weekStart: .monday, now: [2026, 1, 1, 12, 0], expected: [2025, 12, 29]),
        // Late on Sunday evening in Los Angeles it is already Monday in UTC: the lifter's own week counts.
        Row(zone: "America/Los_Angeles", weekStart: .monday, now: [2026, 9, 13, 22, 20], expected: [2026, 9, 7]),
        Row(zone: "America/Los_Angeles", weekStart: .sunday, now: [2026, 9, 13, 22, 20], expected: [2026, 9, 13]),
        // Havana skips midnight on Sunday 2026-03-08 (DST): the day, and a Sunday-start week, begin at 01:00.
        Row(zone: "America/Havana", weekStart: .sunday, now: [2026, 3, 7, 23, 59], expected: [2026, 3, 1]),
        Row(zone: "America/Havana", weekStart: .sunday, now: [2026, 3, 8, 1, 0], expected: [2026, 3, 8]),
        Row(zone: "America/Havana", weekStart: .sunday, now: [2026, 3, 14, 23, 59], expected: [2026, 3, 8]),
        Row(zone: "America/Havana", weekStart: .sunday, now: [2026, 3, 15, 0, 0], expected: [2026, 3, 15]),
        Row(zone: "America/Havana", weekStart: .monday, now: [2026, 3, 8, 1, 0], expected: [2026, 3, 2]),
        // Cairo skips midnight on Friday 2026-04-24.
        Row(zone: "Africa/Cairo", weekStart: .friday, now: [2026, 4, 23, 23, 59], expected: [2026, 4, 17]),
        Row(zone: "Africa/Cairo", weekStart: .friday, now: [2026, 4, 24, 1, 0], expected: [2026, 4, 24])
    ]

    private func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Fixtures.calendar
        calendar.timeZone = zone
        return calendar
    }

    @Test("The start date is the first day of the week that holds the instant, in the calendar's zone", arguments: rows)
    func startDate_isTheFirstDayOfTheWeek(row: Row) throws {
        let zone = try Fixtures.zone(row.zone)
        let calendar = calendar(in: zone)
        let now = Fixtures.date(row.now[0], row.now[1], row.now[2], hour: row.now[3], minute: row.now[4], in: zone)
        let start = try #require(
            ProgramTemplates.startDate(containing: now, weekStart: row.weekStart, calendar: calendar)
        )
        #expect(start == Fixtures.civil(row.expected[0], row.expected[1], row.expected[2]))
        #expect(start.weekday == row.weekStart)
        // The lifter is in week 1 of a block that starts on that date.
        let weeks = WeekCalendar(startDate: start, weekStart: row.weekStart, calendar: calendar)
        #expect(weeks.weekIndex(for: now) == 0)
        #expect(weeks.bounds(ofWeek: 0).contains(now))
    }

    @Test("For every week start, the date is on that weekday and at most six days back", arguments: Weekday.allCases)
    func startDate_isOnTheWeekStart_atMostSixDaysBack(weekStart: Weekday) throws {
        for day in 7 ... 20 {
            let now = Fixtures.date(2026, 9, day, hour: 12)
            let today = Fixtures.civil(2026, 9, day)
            let start = try #require(
                ProgramTemplates.startDate(containing: now, weekStart: weekStart, calendar: Fixtures.calendar)
            )
            #expect(start.weekday == weekStart, "\(today)")
            #expect((0 ... 6).contains(today.days(since: start)), "\(today)")
        }
    }

    @Test("The week start given wins over the calendar's own first weekday")
    func startDate_ignoresTheCalendarsFirstWeekday() {
        var sundayFirst = Fixtures.calendar
        sundayFirst.firstWeekday = 1
        var mondayFirst = Fixtures.calendar
        mondayFirst.firstWeekday = 2
        for calendar in [sundayFirst, mondayFirst] {
            let monday = ProgramTemplates.startDate(containing: Fixtures.now, weekStart: .monday, calendar: calendar)
            let sunday = ProgramTemplates.startDate(containing: Fixtures.now, weekStart: .sunday, calendar: calendar)
            #expect(monday == Fixtures.civil(2026, 9, 14))
            #expect(sunday == Fixtures.civil(2026, 9, 13))
        }
    }

    @Test("Criterion 11: set up on Wednesday 2026-09-16, the block starts on Monday the 14th and is in week 1")
    func startDate_criterion11_wednesdayIsInWeek1() throws {
        let start = try #require(
            ProgramTemplates.startDate(containing: Fixtures.now, weekStart: .monday, calendar: Fixtures.calendar)
        )
        var next = 0
        let program = try ProgramTemplates.program(
            ProgramTemplates.Request(goal: .both, days: .four, units: .lb, startDate: start),
            catalog: BundledCatalog.exercises(),
            id: Fixtures.programID,
            newID: {
                next += 1
                return Fixtures.uuid(next)
            }
        )
        #expect(program.startDate == Fixtures.civil(2026, 9, 14))
        let weeks = WeekCalendar(startDate: program.startDate, weekStart: .monday, calendar: Fixtures.calendar)
        #expect(weeks.weekIndex(for: Fixtures.now) == 0)
        #expect(!weeks.isBlockComplete(program, on: Fixtures.now))
        // Wednesday of week 1 is Lower A.
        let today = try #require(weeks.scheduledDay(on: Fixtures.now, in: program))
        #expect(program.days.first { $0.id == today }?.tag == "LA")
    }

    @Test("An instant whose week starts outside the years 1…9999 has no start date")
    func startDate_outOfRange_isNil() {
        for seconds in [1e12, -1e12] {
            let now = Date(timeIntervalSince1970: seconds)
            #expect(ProgramTemplates.startDate(containing: now, weekStart: .monday, calendar: Fixtures.calendar) == nil)
        }
    }
}
