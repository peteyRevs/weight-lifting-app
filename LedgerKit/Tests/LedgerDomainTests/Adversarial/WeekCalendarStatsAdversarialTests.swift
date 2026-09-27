import Foundation
@testable import LedgerDomain
import Testing

/// A civil date (UTC) and its expected ISO 8601 week key.
struct IsoCase: Sendable, CustomStringConvertible {
    let date: Date
    let year: Int
    let week: Int
    let description: String

    init(_ year: Int, _ month: Int, _ day: Int, _ keyYear: Int, _ keyWeek: Int) {
        date = Fixtures.date(year, month, day)
        self.year = keyYear
        week = keyWeek
        description = "\(year)-\(month)-\(day)"
    }
}

/// Stats weeks, week keys and block helpers (decisions #4, #15, #18).
@Suite("WeekCalendar stats weeks (adversarial)", .tags(.domain))
struct WeekCalendarStatsAdversarialTests {
    typealias Base = WeekCalendarAdversarialTests
}

extension WeekCalendarStatsAdversarialTests {
    @Test("A Sunday week start puts Wed Sep 16 in Sep 13–20 and its previous week at Sep 6–13 (decision #15).")
    func sundayStart_weeks() {
        let weeks = Base.weeks(weekStart: .sunday)
        #expect(weeks.week(containing: Base.day(2026, 9, 16)) == Base.day(2026, 9, 13) ..< Base.day(2026, 9, 20))
        #expect(weeks.week(containing: Base.day(2026, 9, 13)) == Base.day(2026, 9, 13) ..< Base.day(2026, 9, 20))
        #expect(weeks.week(containing: Base.day(2026, 9, 19, 23, 59)) == Base.day(2026, 9, 13) ..< Base.day(
            2026,
            9,
            20
        ))
        #expect(weeks.previousCompleteWeek(before: Base.day(2026, 9, 16)) == Base.day(2026, 9, 6) ..< Base.day(
            2026,
            9,
            13
        ))
    }

    @Test("The Settings week start wins over the calendar's own first weekday (decision #15 override).")
    func weekStart_overridesCalendarFirstWeekday() {
        let monday = Base.weeks(weekStart: .monday, firstWeekday: 1)
        let sunday = Base.weeks(weekStart: .sunday, firstWeekday: 2)
        #expect(monday.week(containing: Base.day(2026, 9, 13)) == Base.day(2026, 9, 7) ..< Base.day(2026, 9, 14))
        #expect(sunday.week(containing: Base.day(2026, 9, 14)) == Base.day(2026, 9, 13) ..< Base.day(2026, 9, 20))
    }

    @Test("At a week's first instant the previous complete week is the one just ended.")
    func previousCompleteWeek_atBoundary() {
        let weeks = Base.weeks()
        #expect(weeks.previousCompleteWeek(before: Base.day(2026, 9, 14)) == Base.day(2026, 9, 7) ..< Base.day(
            2026,
            9,
            14
        ))
    }

    @Test(
        "Monday-start week keys are ISO 8601 weeks, including year-straddling weeks (decision #4).",
        arguments: [
            IsoCase(2026, 1, 1, 2026, 1), IsoCase(2025, 12, 29, 2026, 1), IsoCase(2027, 1, 1, 2026, 53),
            IsoCase(2021, 1, 3, 2020, 53), IsoCase(2024, 12, 30, 2025, 1), IsoCase(2026, 9, 16, 2026, 38),
            IsoCase(2026, 12, 31, 2026, 53), IsoCase(2026, 1, 5, 2026, 2)
        ]
    )
    func isoWeekKey_mondayStart(row: IsoCase) {
        let key = Base.weeks().isoWeekKey(for: row.date)
        let (year, week) = (row.year, row.week)
        #expect(key == WeekKey(year: year, week: week))
    }

    @Test("Sunday-start week keys use the 'week holding the 4th day' rule: Jan 1 2026 is 2025-W53.")
    func isoWeekKey_sundayStart() {
        // Sunday weeks: week 1 of 2026 is Sun Jan 4 – Sat Jan 10, so Thu Jan 1 is the last week of 2025.
        let weeks = Base.weeks(weekStart: .sunday)
        #expect(weeks.isoWeekKey(for: Base.day(2026, 1, 1)) == WeekKey(year: 2025, week: 53))
        #expect(weeks.isoWeekKey(for: Base.day(2026, 1, 4)) == WeekKey(year: 2026, week: 1))
    }

    @Test("Only the passed calendar's time zone is used: a non-Gregorian calendar gives Gregorian answers.")
    func nonGregorianCalendar_usesTimeZoneOnly() {
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = Fixtures.utc
        let weeks = WeekCalendar(startDate: Adversarial.startDay, weekStart: .monday, calendar: islamic)
        #expect(weeks.weekIndex(for: Base.day(2026, 9, 14)) == 4)
        #expect(weeks.weekday(of: Base.day(2026, 8, 19)) == .wednesday)
        #expect(weeks.previousCompleteWeek(before: Base.day(2026, 9, 16)) == Base.day(2026, 9, 7) ..< Base.day(
            2026,
            9,
            14
        ))
        #expect(weeks.isoWeekKey(for: Base.day(2026, 9, 16)) == WeekKey(year: 2026, week: 38))
    }

    @Test("Week keys order by year, then week.")
    func weekKey_ordering() {
        let keys = [WeekKey(year: 2026, week: 2), WeekKey(year: 2025, week: 53), WeekKey(year: 2026, week: 1)]
        #expect(keys.sorted() == [
            WeekKey(year: 2025, week: 53),
            WeekKey(year: 2026, week: 1),
            WeekKey(year: 2026, week: 2)
        ])
    }

    @Test("Scheduled days, block end and skipped weeks follow the program (decision #18).")
    func blockHelpers() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let weeks = Base.weeks()
        #expect(weeks.scheduledDay(on: Base.day(2026, 8, 17, 7), in: program) == program.days[0].id)
        #expect(weeks.scheduledDay(on: Base.day(2026, 8, 19, 7), in: program) == program.days[1].id)
        #expect(weeks.scheduledDay(on: Base.day(2026, 8, 18, 7), in: program) == nil)
        #expect(weeks.scheduledDay(on: Base.day(2026, 8, 10, 7), in: program) == nil)
        #expect(weeks.scheduledDay(on: Base.day(2026, 10, 12, 7), in: program) == nil)
        #expect(!weeks.isBlockComplete(program, on: Base.day(2026, 10, 11, 23)))
        #expect(weeks.isBlockComplete(program, on: Base.day(2026, 10, 12)))
        #expect(weeks.skippedWeeks(before: Base.day(2026, 9, 9), trainedWeeks: [0, 2], weekCount: 8) == [1])
        #expect(weeks.skippedWeeks(before: Base.day(2026, 8, 19), trainedWeeks: [], weekCount: 8).isEmpty)
        #expect(weeks.skippedWeeks(before: Base.day(2027, 1, 1), trainedWeeks: [0, 1, 2, 3, 4, 5], weekCount: 8) == [
            6,
            7
        ])
    }
}

@Suite("WeekCalendar properties (adversarial)", .tags(.domain, .property))
struct WeekCalendarPropertyAdversarialTests {
    typealias Base = WeekCalendarAdversarialTests

    static let zones = [
        "UTC", "America/New_York", "Europe/Berlin", "Australia/Sydney", "Australia/Lord_Howe", "America/Santiago",
        "America/Havana", "Asia/Kolkata", "Pacific/Chatham", "Pacific/Kiritimati"
    ]

    /// The civil date of `date` in `calendar`'s zone as a day count (immune to missing midnights).
    static func dayNumber(_ date: Date, _ calendar: Calendar) throws -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let civil = try #require(Base.calendar().date(from: parts))
        return Int(civil.timeIntervalSinceReferenceDate / 86400)
    }
}

extension WeekCalendarPropertyAdversarialTests {
    @Test(
        "Program weeks, weekdays and stats weeks agree with Foundation calendar-day arithmetic.",
        arguments: PropertySeed.all(plus: [4_664_308, 7_823_989, 9_708_711, 12_535_794, 15_212_416])
    )
    func weeks_agreeWithCalendarDays(seed: PropertySeed) throws {
        var generator = seed.generator
        let zone = try Fixtures.zone(Self.zones.randomElement(using: &generator) ?? "UTC")
        let calendar = Base.calendar(zone)
        let start = Base.day(2020, 1, 1, in: zone).addingTimeInterval(Double(Int.random(
            in: 0 ... 3650,
            using: &generator
        )) * 86400)
        let date = start.addingTimeInterval(Double(Int.random(in: -86400 * 60 ... 86400 * 400, using: &generator)))
        let weekStart = Weekday.allCases.randomElement(using: &generator) ?? .monday
        let weeks = try WeekCalendar(
            startDate: #require(CivilDate(start, in: calendar)),
            weekStart: weekStart,
            calendar: calendar
        )
        let days = try Self.dayNumber(date, calendar) - Self.dayNumber(start, calendar)
        let index = Int((Double(days) / 7).rounded(.down))
        let context = "\(zone.identifier) start \(start) date \(date)"
        #expect(weeks.weekIndex(for: date) == index, "\(context)")
        #expect(weeks.bounds(ofWeek: index).contains(date), "\(context)")
        let expectedLower = calendar.date(byAdding: .day, value: 7 * index, to: calendar.startOfDay(for: start))
        #expect(weeks.bounds(ofWeek: index).lowerBound == expectedLower.map(calendar.startOfDay(for:)), "\(context)")
        #expect(
            weeks.weekday(of: date) == Weekday(calendarWeekday: calendar.component(.weekday, from: date)),
            "\(context)"
        )
        let stats = weeks.week(containing: date)
        #expect(stats.contains(date), "\(context)")
        #expect(weeks.weekday(of: stats.lowerBound) == weekStart, "\(context)")
        #expect(calendar.startOfDay(for: stats.lowerBound) == stats.lowerBound, "\(context)")
        #expect(weeks.previousCompleteWeek(before: date).upperBound == stats.lowerBound, "\(context)")
        // Consecutive ranges meet at a start of day: no gap, no overlap.
        #expect(weeks.bounds(ofWeek: index).upperBound == weeks.bounds(ofWeek: index + 1).lowerBound, "\(context)")
        #expect(calendar.startOfDay(for: stats.upperBound) == stats.upperBound, "\(context)")
    }

    @Test("Monday-start week keys equal Foundation's ISO 8601 calendar in the same zone.", arguments: PropertySeed.all)
    func isoWeekKey_matchesISOCalendar(seed: PropertySeed) throws {
        var generator = seed.generator
        let zone = try Fixtures.zone(Self.zones.randomElement(using: &generator) ?? "UTC")
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = zone
        let date = Base.day(2000, 1, 1).addingTimeInterval(Double(Int.random(
            in: 0 ... 86400 * 365 * 40,
            using: &generator
        )))
        let weeks = try WeekCalendar(
            startDate: #require(CivilDate(date, in: Base.calendar(zone))),
            weekStart: .monday,
            calendar: Base.calendar(zone)
        )
        let expected = WeekKey(
            year: iso.component(.yearForWeekOfYear, from: date),
            week: iso.component(.weekOfYear, from: date)
        )
        #expect(weeks.isoWeekKey(for: date) == expected, "\(zone.identifier) \(date)")
    }
}
