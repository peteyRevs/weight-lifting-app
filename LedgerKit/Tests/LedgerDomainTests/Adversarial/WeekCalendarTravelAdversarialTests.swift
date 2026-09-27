import Foundation
@testable import LedgerDomain
import Testing

/// ADR-007: `Program.startDate` is a `CivilDate`, so a block's weeks follow the lifter's wall
/// calendar in whatever zone the app is in; the same local date gives the same week everywhere.
@Suite("WeekCalendar travel and civil start (adversarial, ADR-007)", .tags(.domain))
struct WeekCalendarTravelAdversarialTests {
    typealias Base = WeekCalendarAdversarialTests

    static let zones = [
        "UTC", "America/Los_Angeles", "America/New_York", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago",
        "Africa/Cairo", "America/Santiago", "America/Havana", "Australia/Lord_Howe", "Asia/Kolkata"
    ]

    static func weeks(_ identifier: String, start: CivilDate, weekStart: Weekday = .monday) throws -> WeekCalendar {
        try WeekCalendar(startDate: start, weekStart: weekStart, calendar: Base.calendar(Fixtures.zone(identifier)))
    }

    static func local(
        _ identifier: String,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) throws -> Date {
        try Base.day(2026, month, day, hour, minute, in: Fixtures.zone(identifier))
    }
}

extension WeekCalendarTravelAdversarialTests {
    @Test("The same local date is the same program week in every zone (round-1 spec question 5).", arguments: zones)
    func sameLocalDate_sameWeek(identifier: String) throws {
        let weeks = try Self.weeks(identifier, start: Adversarial.startDay)
        #expect(try weeks.weekIndex(for: Self.local(identifier, 8, 16, 23, 59)) == -1)
        #expect(try weeks.weekIndex(for: Self.local(identifier, 8, 17, 0, 0)) == 0)
        #expect(try weeks.weekIndex(for: Self.local(identifier, 8, 23, 23, 30)) == 0)
        #expect(try weeks.weekIndex(for: Self.local(identifier, 8, 24, 0, 0)) == 1)
        #expect(try weeks.weekIndex(for: Self.local(identifier, 9, 14, 7, 0)) == 4)
        #expect(try weeks.bounds(ofWeek: 1) == Self.local(identifier, 8, 24) ..< Self.local(identifier, 8, 31))
        #expect(try weeks.civilDate(of: Self.local(identifier, 8, 26, 12)) == CivilDate(year: 2026, month: 8, day: 26))
        #expect(try weeks.firstDayOfWeek(containing: Self.local(identifier, 8, 26, 12)) == CivilDate(
            year: 2026,
            month: 8,
            day: 24
        ))
    }

    @Test("The scheduled day and block end follow the local date in any zone (decision #18).", arguments: zones)
    func scheduleAndBlockEnd_followLocalDate(identifier: String) throws {
        let program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let weeks = try Self.weeks(identifier, start: program.startDate)
        #expect(try weeks.scheduledDay(on: Self.local(identifier, 8, 19, 7), in: program) == program.days[1].id)
        #expect(try weeks.scheduledDay(on: Self.local(identifier, 8, 18, 23, 59), in: program) == nil)
        #expect(try !weeks.isBlockComplete(program, on: Self.local(identifier, 10, 11, 23, 59)))
        #expect(try weeks.isBlockComplete(program, on: Self.local(identifier, 10, 12)))
    }

    @Test("One instant can be different local days, and so different weeks, in different zones.")
    func sameInstant_followsLocalDay() throws {
        // Mon 2026-08-24 03:00 UTC is Sun 20:00 in Los Angeles and Mon 12:00 in Tokyo.
        let instant = Fixtures.date(2026, 8, 24, hour: 3)
        #expect(try Self.weeks("America/Los_Angeles", start: Adversarial.startDay).weekIndex(for: instant) == 0)
        #expect(try Self.weeks("Asia/Tokyo", start: Adversarial.startDay).weekIndex(for: instant) == 1)
        #expect(try Self.weeks("America/Los_Angeles", start: Adversarial.startDay).weekday(of: instant) == .sunday)
    }

    @Test("A block starting on a day DST starts at 01:00 begins then, and week 1 still starts at midnight.")
    func havanaStartDay_startsAtOne() throws {
        let zone = try Fixtures.zone("America/Havana")
        let start = try #require(CivilDate(year: 2026, month: 3, day: 8))
        let weeks = WeekCalendar(startDate: start, weekStart: .sunday, calendar: Base.calendar(zone))
        let firstInstant = Base.day(2026, 3, 8, 12, in: zone).addingTimeInterval(-11 * 3600)
        #expect(weeks.bounds(ofWeek: 0) == firstInstant ..< Base.day(2026, 3, 15, in: zone))
        #expect(weeks.bounds(ofWeek: -1) == Base.day(2026, 3, 1, in: zone) ..< firstInstant)
        #expect(weeks.weekIndex(for: firstInstant.addingTimeInterval(-1)) == -1)
        #expect(weeks.weekIndex(for: firstInstant) == 0)
    }

    @Test("A Beirut week holding the skipped midnight still ends at the next Monday's midnight.")
    func beirutWeek_endsAtMidnight() throws {
        // Sun 2026-03-29 00:00 → 01:00 in Beirut.
        let zone = try Fixtures.zone("Asia/Beirut")
        let start = try #require(CivilDate(year: 2026, month: 3, day: 23))
        let weeks = WeekCalendar(startDate: start, weekStart: .monday, calendar: Base.calendar(zone))
        #expect(weeks.bounds(ofWeek: 0) == Base.day(2026, 3, 23, in: zone) ..< Base.day(2026, 3, 30, in: zone))
        #expect(weeks.weekIndex(for: Base.day(2026, 3, 29, 1, 30, in: zone)) == 0)
        #expect(weeks.week(containing: Base.day(2026, 3, 29, 12, in: zone)) == weeks.bounds(ofWeek: 0))
    }

    @Test("A Friday week start in Cairo begins its transition week at that Friday's 01:00 (decision #15).")
    func cairoFridayWeekStart() throws {
        let zone = try Fixtures.zone("Africa/Cairo")
        let weeks = WeekCalendar(startDate: Adversarial.startDay, weekStart: .friday, calendar: Base.calendar(zone))
        let friday = Base.day(2026, 4, 24, 12, in: zone).addingTimeInterval(-11 * 3600)
        #expect(weeks.firstDayOfWeek(containing: Base.day(2026, 4, 27, in: zone)) == CivilDate(
            year: 2026,
            month: 4,
            day: 24
        ))
        #expect(weeks.week(containing: Base.day(2026, 4, 27, in: zone)) == friday ..< Base.day(2026, 5, 1, in: zone))
        #expect(weeks.previousCompleteWeek(before: Base.day(2026, 5, 2, in: zone)) == friday ..< Base.day(
            2026,
            5,
            1,
            in: zone
        ))
    }
}

@Suite("WeekCalendar travel properties (adversarial, ADR-007)", .tags(.domain, .property))
struct TravelPropertyAdversarialTests {}

extension TravelPropertyAdversarialTests {
    @Test("Two zones agree on week, weekday and week start for the same local date-time.", arguments: PropertySeed.all)
    func twoZones_agreeOnLocalDateTime(seed: PropertySeed) throws {
        var generator = seed.generator
        let zones = WeekCalendarTravelAdversarialTests.zones
        let first = zones.randomElement(using: &generator) ?? "UTC"
        let second = zones.randomElement(using: &generator) ?? "UTC"
        let start = try #require(CivilDate(year: 2000, month: 1, day: 1)?.adding(days: Int.random(
            in: 0 ... 14000,
            using: &generator
        )))
        let local = try #require(start.adding(days: Int.random(in: -60 ... 400, using: &generator)))
        let hour = Int.random(in: 0 ... 23, using: &generator)
        let minute = Int.random(in: 0 ... 59, using: &generator)
        let weekStart = Weekday.allCases.randomElement(using: &generator) ?? .monday
        var results: [String] = []
        for identifier in [first, second] {
            let zone = try Fixtures.zone(identifier)
            let weeks = WeekCalendar(
                startDate: start,
                weekStart: weekStart,
                calendar: WeekCalendarAdversarialTests.calendar(zone)
            )
            // A local time inside a DST gap resolves later on the same civil day, never to another day.
            let instant = Fixtures.date(local.year, local.month, local.day, hour: hour, minute: minute, in: zone)
            #expect(weeks.civilDate(of: instant) == local, "\(identifier) \(local) \(hour):\(minute)")
            let index = weeks.weekIndex(for: instant)
            #expect(index == Int((Double(local.days(since: start)) / 7).rounded(.down)), "\(identifier)")
            #expect(weeks.bounds(ofWeek: index).contains(instant), "\(identifier) \(local) \(hour):\(minute)")
            #expect(weeks.firstDayOfWeek(containing: instant)?.weekday == weekStart)
            let firstDay = String(describing: weeks.firstDayOfWeek(containing: instant))
            results.append("\(index) \(weeks.weekday(of: instant)) \(firstDay)")
        }
        #expect(results[0] == results[1], "\(first) vs \(second) at \(local) \(hour):\(minute)")
    }

    @Test("Every program week starts at the start of its own civil day, in any zone.", arguments: PropertySeed.all)
    func bounds_areStartsOfCivilDays(seed: PropertySeed) throws {
        var generator = seed.generator
        let zones = WeekCalendarTravelAdversarialTests.zones + ["Asia/Beirut", "America/Asuncion", "Asia/Tehran"]
        let zone = try Fixtures.zone(zones.randomElement(using: &generator) ?? "UTC")
        let calendar = WeekCalendarAdversarialTests.calendar(zone)
        let start = try #require(CivilDate(year: 2005, month: 1, day: 1)?.adding(days: Int.random(
            in: 0 ... 9000,
            using: &generator
        )))
        let weeks = WeekCalendar(startDate: start, weekStart: .monday, calendar: calendar)
        let index = Int.random(in: -10 ... 60, using: &generator)
        let bounds = weeks.bounds(ofWeek: index)
        #expect(
            try bounds.lowerBound == #require(start.adding(days: 7 * index)).startOfDay(in: calendar),
            "\(zone.identifier) \(start)"
        )
        #expect(try bounds.upperBound == #require(start.adding(days: 7 * index + 7)).startOfDay(in: calendar))
        #expect(CivilDate(bounds.lowerBound, in: calendar) == start.adding(days: 7 * index))
        #expect(CivilDate(bounds.upperBound.addingTimeInterval(-1), in: calendar) == start.adding(days: 7 * index + 6))
    }
}
