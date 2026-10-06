import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 1: `WeekCalendar.nextScheduledDay(after:in:)` against the brief's dated
/// examples and hand-computed dates. Spec §6.4's seed begun on Monday 2026-09-14 trains Mon UA ·
/// Wed LA · Fri UB · Sat LB in weeks 1–7 and Mon · Wed · Fri in week 8.
@Suite("WeekCalendar.nextScheduledDay (adversarial, F09 S2)", .tags(.domain))
struct NextScheduledDayAdversarialTests {
    typealias Support = ScheduleAdversarial

    /// One hand-computed row: the wall-clock moment asked about and the session expected after it.
    struct Row: Sendable, CustomStringConvertible {
        let day: String
        var hour = 12
        var minute = 0
        var second = 0
        let next: String?
        var weekIndex = 0
        var tag = ""
        var weekday = Weekday.monday

        var description: String {
            "after \(day) \(hour):\(minute):\(second) → \(next ?? "nil")"
        }

        func expected() throws -> ScheduledDay? {
            guard let next else {
                return nil
            }
            let days = [Support.upperA, Support.lowerA, Support.upperB, Support.lowerB]
            let template = try #require(days.first { $0.tag == tag })
            let date = try #require(CivilDate(iso8601: next))
            return ScheduledDay(date: date, weekIndex: weekIndex, dayTemplateID: template.id)
        }

        func moment(in zone: TimeZone) throws -> Date {
            try Support.moment(#require(CivilDate(iso8601: day)), hour, minute, second, in: zone)
        }
    }

    static let briefRows = [
        Row(day: "2026-09-16", hour: 0, next: "2026-09-18", tag: "UB", weekday: .friday),
        Row(day: "2026-09-16", hour: 5, minute: 20, next: "2026-09-18", tag: "UB", weekday: .friday),
        Row(day: "2026-09-16", hour: 23, minute: 59, second: 59, next: "2026-09-18", tag: "UB", weekday: .friday),
        Row(day: "2026-09-19", next: "2026-09-21", weekIndex: 1, tag: "UA", weekday: .monday),
        Row(day: "2026-09-20", hour: 23, minute: 59, second: 59, next: "2026-09-21", weekIndex: 1, tag: "UA"),
        Row(day: "2026-11-06", hour: 0, next: nil),
        Row(day: "2026-11-06", hour: 23, minute: 59, second: 59, next: nil)
    ]

    static let blockRows = [
        Row(day: "2026-09-14", hour: 0, next: "2026-09-16", tag: "LA", weekday: .wednesday),
        Row(day: "2026-09-15", next: "2026-09-16", tag: "LA", weekday: .wednesday),
        Row(day: "2026-09-17", next: "2026-09-18", tag: "UB", weekday: .friday),
        Row(day: "2026-09-18", next: "2026-09-19", tag: "LB", weekday: .saturday),
        Row(day: "2026-10-30", next: "2026-10-31", weekIndex: 6, tag: "LB", weekday: .saturday),
        Row(day: "2026-10-31", next: "2026-11-02", weekIndex: 7, tag: "UA", weekday: .monday),
        Row(day: "2026-11-01", hour: 23, minute: 59, second: 59, next: "2026-11-02", weekIndex: 7, tag: "UA"),
        Row(day: "2026-11-02", next: "2026-11-04", weekIndex: 7, tag: "LA", weekday: .wednesday),
        Row(day: "2026-11-04", next: "2026-11-06", weekIndex: 7, tag: "UB", weekday: .friday),
        Row(
            day: "2026-11-05",
            hour: 23,
            minute: 59,
            second: 59,
            next: "2026-11-06",
            weekIndex: 7,
            tag: "UB",
            weekday: .friday
        ),
        Row(day: "2026-11-07", next: nil),
        Row(day: "2026-11-08", hour: 23, minute: 59, second: 59, next: nil),
        Row(day: "2026-11-09", hour: 0, next: nil),
        Row(day: "2027-01-01", next: nil),
        Row(day: "2026-09-13", hour: 23, minute: 59, second: 59, next: "2026-09-14", tag: "UA"),
        Row(day: "2026-09-07", next: "2026-09-14", tag: "UA"),
        Row(day: "2026-01-01", next: "2026-09-14", tag: "UA"),
        Row(day: "1999-12-31", next: "2026-09-14", tag: "UA")
    ]

    static let zones = [
        "UTC", "Pacific/Kiritimati", "Etc/GMT+12", "Pacific/Pago_Pago", "Pacific/Chatham", "Asia/Kathmandu",
        "America/Chicago", "Africa/Cairo", "America/Havana", "Australia/Lord_Howe"
    ]
}

extension NextScheduledDayAdversarialTests {
    @Test("The brief's three dated examples hold at every time of the day asked about.", arguments: briefRows)
    func nextScheduledDay_briefExamples_matchTheBrief(row: Row) throws {
        let program = try Support.seedProgram()
        let next = try Support.weeks().nextScheduledDay(after: row.moment(in: Fixtures.utc), in: program)
        #expect(try next == row.expected())
        if let next {
            #expect(next.weekday == row.weekday)
        }
    }

    @Test(
        "Before the block, on its first day, through its last session and after it, in every zone and week start.",
        arguments: briefRows + blockRows
    )
    func nextScheduledDay_throughTheBlock_matchesHandComputedDays(row: Row) throws {
        let program = try Support.seedProgram()
        for identifier in Self.zones {
            let zone = try Fixtures.zone(identifier)
            for weekStart in Weekday.allCases {
                let weeks = Support.weeks(weekStart: weekStart, zone: zone)
                let next = try weeks.nextScheduledDay(after: row.moment(in: zone), in: program)
                #expect(try next == row.expected(), "\(identifier), weeks start on \(weekStart)")
                #expect(next.map(\.weekday) == next.map(\.date.weekday))
            }
        }
    }

    @Test("One instant is two different days at the two ends of UTC, and each zone answers for its own day.")
    func nextScheduledDay_sameInstantAtBothExtremes_followsEachZonesDay() throws {
        let program = try Support.seedProgram()
        // 2026-09-16 11:00 UTC is Thursday 01:00 on Kiritimati (UTC+14) and Tuesday 23:00 at UTC−12.
        let instant = Fixtures.date(2026, 9, 16, hour: 11)
        let east = try Support.weeks(zone: Fixtures.zone("Pacific/Kiritimati"))
        let west = try Support.weeks(zone: Fixtures.zone("Etc/GMT+12"))
        let friday = ScheduledDay(date: Fixtures.civil(2026, 9, 18), weekIndex: 0, dayTemplateID: Support.upperB.id)
        let wednesday = ScheduledDay(date: Fixtures.civil(2026, 9, 16), weekIndex: 0, dayTemplateID: Support.lowerA.id)
        #expect(east.nextScheduledDay(after: instant, in: program) == friday)
        #expect(west.nextScheduledDay(after: instant, in: program) == wednesday)
    }

    @Test(
        "One second before midnight belongs to the old day and midnight to the new one, at UTC+14 and UTC−12.",
        arguments: [("Pacific/Kiritimati", 10, 15), ("Etc/GMT+12", 12, 16)]
    )
    func nextScheduledDay_aroundMidnightAtTheExtremes_changesExactlyAtMidnight(
        identifier: String,
        utcHour: Int,
        utcDay: Int
    ) throws {
        let program = try Support.seedProgram()
        let weeks = try Support.weeks(zone: Fixtures.zone(identifier))
        // Local midnight starting Wednesday 2026-09-16, written as its UTC instant.
        let midnight = Fixtures.date(2026, 9, utcDay, hour: utcHour)
        let wednesday = ScheduledDay(date: Fixtures.civil(2026, 9, 16), weekIndex: 0, dayTemplateID: Support.lowerA.id)
        let friday = ScheduledDay(date: Fixtures.civil(2026, 9, 18), weekIndex: 0, dayTemplateID: Support.upperB.id)
        #expect(weeks.nextScheduledDay(after: midnight.addingTimeInterval(-1), in: program) == wednesday)
        #expect(weeks.nextScheduledDay(after: midnight.addingTimeInterval(-0.001), in: program) == wednesday)
        #expect(weeks.nextScheduledDay(after: midnight, in: program) == friday)
        #expect(weeks.nextScheduledDay(after: midnight.addingTimeInterval(1), in: program) == friday)
    }

    @Test(
        "Only the calendar's time zone is read: its identifier and first weekday change nothing.",
        arguments: [Calendar.Identifier.buddhist, .hebrew, .islamicCivil, .japanese, .persian, .iso8601]
    )
    func nextScheduledDay_nonGregorianCalendar_answersInGregorianDays(identifier: Calendar.Identifier) throws {
        let program = try Support.seedProgram()
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = Fixtures.utc
        calendar.firstWeekday = 5
        calendar.minimumDaysInFirstWeek = 7
        let weeks = WeekCalendar(startDate: Support.seedStart, weekStart: .thursday, calendar: calendar)
        for row in Self.briefRows + Self.blockRows {
            #expect(try weeks.nextScheduledDay(after: row.moment(in: Fixtures.utc), in: program) == row.expected())
        }
    }

    @Test("ScheduledDay reads its weekday from its date and is equal when its three stored values are.")
    func scheduledDay_weekdayAndEquality_followTheStoredValues() {
        let friday = ScheduledDay(date: Fixtures.civil(2026, 9, 18), weekIndex: 0, dayTemplateID: Support.upperB.id)
        #expect(friday.weekday == .friday)
        #expect(friday.date == Fixtures.civil(2026, 9, 18))
        #expect(friday.weekIndex == 0)
        #expect(friday.dayTemplateID == Support.upperB.id)
        let same = ScheduledDay(date: Fixtures.civil(2026, 9, 18), weekIndex: 0, dayTemplateID: Support.upperB.id)
        #expect(friday == same)
        #expect(friday.hashValue == same.hashValue)
        #expect(friday != ScheduledDay(
            date: Fixtures.civil(2026, 9, 18),
            weekIndex: 1,
            dayTemplateID: Support.upperB.id
        ))
        #expect(friday != ScheduledDay(
            date: Fixtures.civil(2026, 9, 19),
            weekIndex: 0,
            dayTemplateID: Support.upperB.id
        ))
        #expect(friday != ScheduledDay(
            date: Fixtures.civil(2026, 9, 18),
            weekIndex: 0,
            dayTemplateID: Support.upperA.id
        ))
        let weekdays = (14 ... 20).map { ScheduledDay(
            date: Fixtures.civil(2026, 9, $0), weekIndex: 0, dayTemplateID: Support.upperA.id
        ).weekday }
        #expect(weekdays == Weekday.allCases)
    }
}
