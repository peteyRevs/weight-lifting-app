import Foundation
@testable import LedgerDomain
import Testing

@Suite("WeekCalendar (adversarial)", .tags(.domain))
struct WeekCalendarAdversarialTests {
    static func calendar(_ zone: TimeZone = Fixtures.utc, firstWeekday: Int = 1) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = zone
        gregorian.firstWeekday = firstWeekday
        return gregorian
    }

    static func weeks(
        start: Date = Adversarial.start,
        weekStart: Weekday = .monday,
        zone: TimeZone = Fixtures.utc,
        firstWeekday: Int = 1
    ) -> WeekCalendar {
        let calendar = calendar(zone, firstWeekday: firstWeekday)
        return WeekCalendar(
            startDate: Adversarial.civilDay(start, in: calendar),
            weekStart: weekStart,
            calendar: calendar
        )
    }

    static func day(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        in zone: TimeZone = Fixtures.utc
    ) -> Date {
        Fixtures.date(year, month, day, hour: hour, minute: minute, in: zone)
    }
}

extension WeekCalendarAdversarialTests {
    @Test("Aug 19 is week 0 (Wednesday), Sep 14 is week 4, and the week before Sep 16 is Sep 7–14 (criterion 10).")
    func criterion10() {
        let weeks = Self.weeks()
        #expect(weeks.weekIndex(for: Self.day(2026, 8, 19)) == 0)
        #expect(weeks.weekday(of: Self.day(2026, 8, 19)) == .wednesday)
        #expect(weeks.weekIndex(for: Self.day(2026, 9, 14)) == 4)
        #expect(weeks.previousCompleteWeek(before: Self.day(2026, 9, 16)) == Self.day(2026, 9, 7) ..< Self.day(
            2026,
            9,
            14
        ))
    }

    @Test(
        "Dates before the start date floor to negative weeks (decision #18).",
        arguments: [(16, 23, -1), (16, 0, -1), (10, 0, -1), (9, 23, -2), (17, 0, 0), (23, 23, 0), (24, 0, 1)]
    )
    func weekIndex_aroundStart_floors(day: Int, hour: Int, week: Int) {
        #expect(Self.weeks().weekIndex(for: Self.day(2026, 8, day, hour)) == week)
    }

    @Test("A start date with a time of day still counts whole calendar days from its midnight.")
    func weekIndex_startWithTime_usesStartOfDay() {
        let weeks = Self.weeks(start: Self.day(2026, 8, 17, 15))
        #expect(weeks.weekIndex(for: Self.day(2026, 8, 17, 1)) == 0)
        #expect(weeks.weekIndex(for: Self.day(2026, 8, 24, 9)) == 1)
        #expect(weeks.bounds(ofWeek: 0) == Self.day(2026, 8, 17) ..< Self.day(2026, 8, 24))
    }

    @Test("Program week bounds are consecutive 7-day ranges, including negative indices.")
    func bounds_consecutiveWeeks() {
        let weeks = Self.weeks()
        #expect(weeks.bounds(ofWeek: -1) == Self.day(2026, 8, 10) ..< Self.day(2026, 8, 17))
        #expect(weeks.bounds(ofWeek: 4) == Self.day(2026, 9, 14) ..< Self.day(2026, 9, 21))
        #expect(weeks.bounds(ofWeek: 20).lowerBound == Self.day(2027, 1, 4))
    }

    @Test("New York spring-forward week is 167 hours and still one program week (decision #18, DST).")
    func dst_newYorkSpring() throws {
        let zone = try Fixtures.zone("America/New_York")
        let weeks = Self.weeks(start: Self.day(2026, 3, 2, in: zone), zone: zone)
        #expect(weeks.weekIndex(for: Self.day(2026, 3, 8, 23, 30, in: zone)) == 0)
        #expect(weeks.weekIndex(for: Self.day(2026, 3, 9, 0, 30, in: zone)) == 1)
        let week0 = weeks.bounds(ofWeek: 0)
        #expect(week0 == Self.day(2026, 3, 2, in: zone) ..< Self.day(2026, 3, 9, in: zone))
        #expect(week0.upperBound.timeIntervalSince(week0.lowerBound) == 167 * 3600)
        #expect(weeks.weekday(of: Self.day(2026, 3, 8, 23, 30, in: zone)) == .sunday)
        #expect(
            weeks.previousCompleteWeek(before: Self.day(2026, 3, 11, in: zone))
                == Self.day(2026, 3, 2, in: zone) ..< Self.day(2026, 3, 9, in: zone)
        )
    }

    @Test("New York fall-back week is 169 hours and still one program week.")
    func dst_newYorkFall() throws {
        let zone = try Fixtures.zone("America/New_York")
        let weeks = Self.weeks(start: Self.day(2026, 10, 26, in: zone), zone: zone)
        let week0 = weeks.bounds(ofWeek: 0)
        #expect(week0.upperBound.timeIntervalSince(week0.lowerBound) == 169 * 3600)
        #expect(weeks.weekIndex(for: Self.day(2026, 11, 1, 23, 59, in: zone)) == 0)
        #expect(weeks.weekIndex(for: Self.day(2026, 11, 2, in: zone)) == 1)
    }

    @Test("Berlin DST weeks in spring and autumn keep Monday midnight boundaries.")
    func dst_berlin() throws {
        let zone = try Fixtures.zone("Europe/Berlin")
        let spring = Self.weeks(start: Self.day(2026, 3, 23, in: zone), zone: zone)
        #expect(spring.weekIndex(for: Self.day(2026, 3, 29, 23, in: zone)) == 0)
        #expect(spring.weekIndex(for: Self.day(2026, 3, 30, in: zone)) == 1)
        let autumn = Self.weeks(start: Self.day(2026, 10, 19, in: zone), zone: zone)
        #expect(autumn.weekIndex(for: Self.day(2026, 10, 25, 12, in: zone)) == 0)
        #expect(autumn.weekIndex(for: Self.day(2026, 10, 26, in: zone)) == 1)
        #expect(autumn.bounds(ofWeek: 1).lowerBound == Self.day(2026, 10, 26, in: zone))
    }

    @Test("A Sunday whose midnight does not exist (Santiago DST) still starts a Sunday week.")
    func dst_santiagoMissingMidnight() throws {
        let zone = try Fixtures.zone("America/Santiago")
        // 2026-09-06 00:00 → 01:00 in Santiago, so that Sunday starts at 01:00.
        let sundayStart = Self.day(2026, 9, 6, 12, in: zone).addingTimeInterval(-11 * 3600)
        let weeks = Self.weeks(start: Self.day(2026, 8, 30, in: zone), weekStart: .sunday, zone: zone)
        #expect(weeks.weekIndex(for: Self.day(2026, 9, 6, 12, in: zone)) == 1)
        #expect(weeks.weekIndex(for: Self.day(2026, 9, 5, 23, 59, in: zone)) == 0)
        #expect(weeks.bounds(ofWeek: 1) == sundayStart ..< Self.day(2026, 9, 13, in: zone))
        #expect(weeks.week(containing: Self.day(2026, 9, 9, in: zone)) == sundayStart ..< Self.day(
            2026,
            9,
            13,
            in: zone
        ))
        // 00:30 on Sun Sep 13 is day 14 → week 2 only; consecutive weeks must not overlap.
        let halfPast = Self.day(2026, 9, 13, 0, 30, in: zone)
        #expect(weeks.weekIndex(for: halfPast) == 2)
        #expect(!weeks.bounds(ofWeek: 1).contains(halfPast))
        #expect(weeks.bounds(ofWeek: 1).upperBound == weeks.bounds(ofWeek: 2).lowerBound)
    }

    @Test("A stats week holding a day without a midnight (Cairo DST) still runs Monday 00:00 to Monday 00:00.")
    func dst_cairoMissingMidnight_statsWeek() throws {
        // 2026-04-24 (Fri) jumps 00:00 → 01:00 in Cairo; the Monday on either side has a real midnight.
        let zone = try Fixtures.zone("Africa/Cairo")
        let weeks = Self.weeks(start: Self.day(2026, 4, 6, in: zone), zone: zone)
        let expected = Self.day(2026, 4, 20, in: zone) ..< Self.day(2026, 4, 27, in: zone)
        #expect(weeks.week(containing: Self.day(2026, 4, 24, 12, in: zone)) == expected)
        #expect(weeks.previousCompleteWeek(before: Self.day(2026, 4, 29, in: zone)) == expected)
        // The same week must not depend on which of its days is asked about.
        #expect(weeks.week(containing: Self.day(2026, 4, 20, 0, 30, in: zone)) == expected)
        #expect(weeks.week(containing: Self.day(2026, 4, 27, 0, 30, in: zone)).lowerBound == expected.upperBound)
    }

    @Test("A block starting on a day without a midnight (Havana DST) keeps later weeks at midnight.")
    func dst_havanaStartWithoutMidnight() throws {
        // Sun 2026-03-08 starts at 01:00 in Havana; Sun Mar 15 has a real midnight.
        let zone = try Fixtures.zone("America/Havana")
        let weeks = Self.weeks(start: Self.day(2026, 3, 8, 12, in: zone), weekStart: .sunday, zone: zone)
        let halfPast = Self.day(2026, 3, 15, 0, 30, in: zone)
        #expect(weeks.weekIndex(for: halfPast) == 1)
        #expect(weeks.bounds(ofWeek: 1) == Self.day(2026, 3, 15, in: zone) ..< Self.day(2026, 3, 22, in: zone))
        #expect(weeks.bounds(ofWeek: weeks.weekIndex(for: halfPast)).contains(halfPast))
        // Five weeks later (Sun Apr 12 00:30) is still the first hour of week 5.
        #expect(weeks.weekIndex(for: Self.day(2026, 4, 12, 0, 30, in: zone)) == 5)
    }

    @Test("Year boundaries: a block starting Dec 29 counts straight through January.")
    func weekIndex_yearBoundary() {
        let weeks = Self.weeks(start: Self.day(2025, 12, 29))
        #expect(weeks.weekIndex(for: Self.day(2026, 1, 4, 23)) == 0)
        #expect(weeks.weekIndex(for: Self.day(2026, 1, 5)) == 1)
        // Dec 31 2026 is 367 days after Dec 29 2025 → week 52.
        #expect(weeks.weekIndex(for: Self.day(2026, 12, 31)) == 52)
        #expect(weeks.previousCompleteWeek(before: Self.day(2026, 1, 7)) == Self.day(2025, 12, 29) ..< Self.day(
            2026,
            1,
            5
        ))
    }
}
