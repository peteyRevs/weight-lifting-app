import Foundation
@testable import LedgerDomain
import Testing

/// F08 S1, G2 round 1: `ProgramTemplates.startDate(containing:weekStart:calendar:)`, decision #18's "first day
/// of the week the user started". Expected days are worked out with Foundation's UTC calendar at noon, apart
/// from `CivilDate`'s own day arithmetic.
@Suite("Adversarial F08 S1 · the start date of a new block (decision #18)", .tags(.domain))
struct TemplatesStartDateAdversarialTests {
    /// Zones whose DST change is at midnight (the day starts at 01:00, or an hour repeats around it), zones at
    /// the date line and half-hour zones, and the two the F02 suites use.
    static let zones = [
        "UTC", "America/Havana", "America/Santiago", "Africa/Cairo", "Asia/Beirut", "America/Asuncion",
        "Pacific/Kiritimati", "Pacific/Pago_Pago", "Australia/Lord_Howe", "Asia/Kolkata", "America/New_York",
        "Europe/Berlin"
    ]

    static func calendar(_ zone: String, _ identifier: Calendar.Identifier = .gregorian) throws -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try Fixtures.zone(zone)
        return calendar
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.utc
        return calendar
    }

    /// The civil day `offset` days after 2026-01-01, as Foundation's UTC calendar counts it.
    static func civil(offset: Int) throws -> CivilDate {
        let noon = Fixtures.date(2026, 1, 1, hour: 12).addingTimeInterval(Double(offset) * 86400)
        let parts = utc.dateComponents([.year, .month, .day], from: noon)
        return try #require(CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0))
    }

    /// The first day, on `weekStart`, of the week holding `day`: Foundation's weekday of `day` (1 = Sunday) says
    /// how many days to go back.
    static func expectedStart(of day: CivilDate, weekStart: Weekday) throws -> CivilDate {
        let noon = Fixtures.date(day.year, day.month, day.day, hour: 12)
        let isoWeekday = (utc.component(.weekday, from: noon) + 5) % 7 + 1
        let back = (isoWeekday - weekStart.rawValue + 7) % 7
        let parts = utc.dateComponents([.year, .month, .day], from: noon.addingTimeInterval(Double(-back) * 86400))
        return try #require(CivilDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0))
    }

    /// Instants of `day` in `calendar`'s zone: its first instant, a second later, noon, and its last second.
    static func instants(of day: CivilDate, in calendar: Calendar) throws -> [Date] {
        func first(_ day: CivilDate) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)))
        }
        let start = try first(day)
        let noon = try #require(calendar.date(
            from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        ))
        let next = try first(#require(day.adding(days: 1)))
        let all = [start, start.addingTimeInterval(1), noon, next.addingTimeInterval(-1)]
        for instant in all {
            let parts = calendar.dateComponents([.year, .month, .day], from: instant)
            let onDay = [parts.year, parts.month, parts.day] == [day.year, day.month, day.day]
            try #require(onDay, "\(instant) is not on \(day) in \(calendar.timeZone.identifier)")
        }
        return all
    }

    @Test(
        "Criterion 11: on Wednesday 2026-09-16 the block starts on the week start on or before it",
        arguments: zip(Weekday.allCases, [14, 15, 16, 10, 11, 12, 13])
    )
    func wednesday_everyWeekStart(weekStart: Weekday, day: Int) {
        let start = ProgramTemplates.startDate(
            containing: Fixtures.now,
            weekStart: weekStart,
            calendar: Fixtures.calendar
        )
        #expect(start == CivilDate(year: 2026, month: 9, day: day))
        #expect(start?.weekday == weekStart)
    }

    @Test(
        "Every day of 2026 and early 2027, at its first and last instants, in every zone and for every week start",
        arguments: zones
    )
    func everyDay_everyWeekStart(zone: String) throws {
        let calendar = try Self.calendar(zone)
        for offset in 0 ..< 380 {
            let day = try Self.civil(offset: offset)
            let instants = try Self.instants(of: day, in: calendar)
            for weekStart in Weekday.allCases {
                let expected = try Self.expectedStart(of: day, weekStart: weekStart)
                for instant in instants {
                    let start = ProgramTemplates.startDate(
                        containing: instant,
                        weekStart: weekStart,
                        calendar: calendar
                    )
                    #expect(start == expected, "\(zone), \(day) at \(instant), week starting \(weekStart)")
                }
            }
        }
    }

    @Test(
        "The block's week 1 is the week it was made in: index 0 from the start day to the last second of the week",
        arguments: zones
    )
    func weekIndex_isZeroForTheWholeFirstWeek(zone: String) throws {
        let calendar = try Self.calendar(zone)
        for offset in 0 ..< 380 {
            let today = try Self.civil(offset: offset)
            let weekStart = Weekday.allCases[offset % 7]
            let now = try Self.instants(of: today, in: calendar)[offset % 4]
            let start = try #require(ProgramTemplates.startDate(
                containing: now,
                weekStart: weekStart,
                calendar: calendar
            ))
            let weeks = WeekCalendar(startDate: start, weekStart: weekStart, calendar: calendar)
            let label = "\(zone), made on \(today), week starting \(weekStart)"
            #expect(start.weekday == weekStart && (0 ... 6).contains(today.days(since: start)), "\(label)")
            #expect(weeks.weekIndex(for: now) == 0, "\(label)")
            #expect(weeks.firstDayOfWeek(containing: now) == start, "\(label)")
            for ahead in 0 ..< 7 {
                let day = try #require(start.adding(days: ahead))
                let indices = try Self.instants(of: day, in: calendar).map { weeks.weekIndex(for: $0) }
                #expect(indices == [0, 0, 0, 0], "\(label): \(day)")
            }
            let before = try Self.instants(of: #require(start.adding(days: -1)), in: calendar)[3]
            let after = try Self.instants(of: #require(start.adding(days: 7)), in: calendar)[0]
            #expect(weeks.weekIndex(for: before) == -1 && weeks.weekIndex(for: after) == 1, "\(label)")
        }
    }
}

// MARK: - Calendars, boundaries and extremes

extension TemplatesStartDateAdversarialTests {
    @Test(
        "Year ends and leap days: the week start can lie in the year, or the February, before",
        arguments: [
            ([2027, 1, 1], Weekday.monday, [2026, 12, 28]), ([2027, 1, 1], .sunday, [2026, 12, 27]),
            ([2027, 1, 1], .friday, [2027, 1, 1]), ([2027, 1, 1], .saturday, [2026, 12, 26]),
            ([2026, 12, 31], .friday, [2026, 12, 25]), ([2028, 2, 29], .monday, [2028, 2, 28]),
            ([2028, 2, 29], .tuesday, [2028, 2, 29]), ([2028, 2, 29], .wednesday, [2028, 2, 23]),
            ([2028, 3, 1], .tuesday, [2028, 2, 29]), ([2028, 3, 4], .tuesday, [2028, 2, 29]),
            ([2027, 3, 1], .saturday, [2027, 2, 27]), ([2100, 3, 1], .sunday, [2100, 2, 28]),
            ([2100, 3, 3], .thursday, [2100, 2, 25]), ([2000, 3, 1], .tuesday, [2000, 2, 29])
        ]
    )
    func boundaries(now: [Int], weekStart: Weekday, expected: [Int]) {
        for hour in [0, 12, 23] {
            let start = ProgramTemplates.startDate(
                containing: Fixtures.date(now[0], now[1], now[2], hour: hour, minute: hour == 23 ? 59 : 0),
                weekStart: weekStart,
                calendar: Fixtures.calendar
            )
            #expect(start == CivilDate(year: expected[0], month: expected[1], day: expected[2]), "at \(hour) h")
        }
    }

    @Test("The zones above do test the hard case: in the days covered, some day starts at 01:00, not midnight")
    func zones_includeASkippedMidnight() throws {
        var skipped: [String] = []
        for zone in ["America/Havana", "America/Santiago", "Africa/Cairo", "Asia/Beirut"] {
            let calendar = try Self.calendar(zone)
            for offset in 0 ..< 380 {
                let first = try Self.instants(of: Self.civil(offset: offset), in: calendar)[0]
                if calendar.component(.hour, from: first) != 0 {
                    try skipped.append("\(zone) \(Self.civil(offset: offset))")
                }
            }
        }
        #expect(skipped.count >= 2, "days without a midnight: \(skipped)")
    }

    @Test("The same instant is a different day, and so a different week, on either side of the date line")
    func dateLine_followsTheLocalDay() throws {
        // 2026-09-14T10:30Z is Tuesday 00:30 on Kiritimati (+14) and Sunday 23:30 in Pago Pago (−11).
        let instant = Fixtures.date(2026, 9, 14, hour: 10, minute: 30)
        let east = try ProgramTemplates.startDate(
            containing: instant, weekStart: .tuesday, calendar: Self.calendar("Pacific/Kiritimati")
        )
        let west = try ProgramTemplates.startDate(
            containing: instant, weekStart: .tuesday, calendar: Self.calendar("Pacific/Pago_Pago")
        )
        #expect(east == CivilDate(year: 2026, month: 9, day: 15))
        #expect(west == CivilDate(year: 2026, month: 9, day: 8))
    }

    @Test(
        "Only the calendar's time zone counts: another calendar system gives the same Gregorian day",
        arguments: [
            Calendar.Identifier.buddhist, .japanese, .hebrew, .islamicUmmAlQura, .persian, .iso8601, .chinese, .indian,
            .coptic, .republicOfChina, .ethiopicAmeteMihret
        ]
    )
    func otherCalendarSystems_giveTheGregorianDay(identifier: Calendar.Identifier) throws {
        for zone in ["UTC", "Asia/Bangkok", "Asia/Tokyo", "Asia/Tehran", "Africa/Cairo"] {
            let other = try Self.calendar(zone, identifier)
            let gregorian = try Self.calendar(zone)
            for offset in stride(from: 0, to: 380, by: 13) {
                let now = try Self.instants(of: Self.civil(offset: offset), in: gregorian)[2]
                for weekStart in Weekday.allCases {
                    let expected = ProgramTemplates.startDate(
                        containing: now,
                        weekStart: weekStart,
                        calendar: gregorian
                    )
                    let start = ProgramTemplates.startDate(containing: now, weekStart: weekStart, calendar: other)
                    #expect(start == expected && start != nil, "\(identifier) in \(zone), \(now), \(weekStart)")
                }
            }
        }
    }

    @Test("The calendar's own first weekday, minimum first week and locale are ignored: the week start given wins")
    func calendarSettings_areIgnored() throws {
        for firstWeekday in 1 ... 7 {
            var calendar = try Self.calendar("America/New_York")
            calendar.firstWeekday = firstWeekday
            calendar.minimumDaysInFirstWeek = firstWeekday
            calendar.locale = Locale(identifier: firstWeekday.isMultiple(of: 2) ? "ar_SA" : "de_DE")
            for weekStart in Weekday.allCases {
                let now = Fixtures.date(2027, 1, 1, hour: 17)
                let start = ProgramTemplates.startDate(containing: now, weekStart: weekStart, calendar: calendar)
                #expect(try start == Self.expectedStart(of: Fixtures.civil(2027, 1, 1), weekStart: weekStart))
            }
        }
    }

    @Test("Instants outside years 1…9999, infinite or not a number give nil; the last valid week has its start")
    func extremes_areNilNotATrap() {
        let far = [-1e300, -9.2e18, -1e15, -1e13, 2.6e11, 1e13, 1e15, 9.2e18, 1e300, .infinity, -.infinity, .nan]
        for seconds in far {
            for weekStart in Weekday.allCases {
                let now = Date(timeIntervalSinceReferenceDate: seconds)
                let start = ProgramTemplates.startDate(
                    containing: now,
                    weekStart: weekStart,
                    calendar: Fixtures.calendar
                )
                #expect(start == nil, "\(seconds) s, week starting \(weekStart)")
            }
        }
        // 9999-12-31 is a Friday.
        let last = Fixtures.date(9999, 12, 31, hour: 23, minute: 59)
        #expect(ProgramTemplates.startDate(containing: last, weekStart: .friday, calendar: Fixtures.calendar)
            == CivilDate(year: 9999, month: 12, day: 31))
        #expect(ProgramTemplates.startDate(containing: last, weekStart: .saturday, calendar: Fixtures.calendar)
            == CivilDate(year: 9999, month: 12, day: 25))
    }

    @Test("Criterion 11 end to end: a block made on Wednesday 2026-09-16 is in week 1 of 8 and trains Lower A today")
    func criterion11_endToEnd() throws {
        let start = try #require(ProgramTemplates.startDate(
            containing: Fixtures.now, weekStart: .monday, calendar: Fixtures.calendar
        ))
        #expect(start == CivilDate(year: 2026, month: 9, day: 14))
        let program = try BriefTemplates.program(
            BriefTemplates.Case(goal: .both, days: .four, units: .lb),
            startDate: start
        )
        let weeks = WeekCalendar(startDate: program.startDate, weekStart: .monday, calendar: Fixtures.calendar)
        #expect(weeks.weekIndex(for: Fixtures.now) == 0 && program.weeks.count == 8)
        #expect(weeks.scheduledDay(on: Fixtures.now, in: program) == program.days[1].id)
        #expect(program.days[1].name == "Lower A — Squat focus")
    }
}
