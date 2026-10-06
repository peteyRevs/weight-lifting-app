import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 1: the answer "does not depend on which weekday the block began or on a stats
/// week that straddles two program weeks", and "after" is a calendar day in the calendar's zone.
/// Every expected value here is `SessionReference`'s, or a date worked out by hand from the zone's
/// 2026 rules (which each test first confirms with Foundation).
@Suite("WeekCalendar.nextScheduledDay across start days, week starts and DST (adversarial, F09 S2)", .tags(.domain))
struct NextScheduledDayMatrixAdversarialTests {
    typealias Support = ScheduleAdversarial

    /// Zones that change at local midnight (Cairo, Santiago, Havana, Beirut, the Azores), one that
    /// drops 23:00 (Nuuk), half-hour and 45-minute zones, both ends of UTC, and two ordinary ones.
    static let zones = [
        "Africa/Cairo", "America/Santiago", "America/Havana", "Asia/Beirut", "Atlantic/Azores", "America/Nuuk",
        "Australia/Lord_Howe", "Pacific/Chatham", "Pacific/Kiritimati", "Etc/GMT+12", "Pacific/Pago_Pago",
        "America/New_York", "Europe/Berlin", "Asia/Kathmandu", "UTC"
    ]

    /// Mondays whose next eight weeks hold every 2026 change of `zones`.
    static let bases = [Fixtures.civil(2026, 3, 2), Fixtures.civil(2026, 8, 31), Fixtures.civil(2026, 10, 5)]

    /// A hand-computed DST case on the every-day block: the instant asked about and the day expected.
    struct Change: Sendable, CustomStringConvertible {
        let zone: String
        let start: String
        let instant: String
        let today: String
        let next: String
        let weekIndex: Int
        let weekday: Weekday

        var description: String {
            "\(zone) \(instant) (\(today)) → \(next)"
        }
    }

    static let changes = [
        // Santiago: midnight of Sunday 2026-09-06 is skipped (Saturday 23:59:59 → Sunday 01:00).
        Change("America/Santiago", "2026-08-31", "2026-09-06T03:59:59Z", "2026-09-05", "2026-09-06", 0, .sunday),
        Change("America/Santiago", "2026-08-31", "2026-09-06T04:00:00Z", "2026-09-06", "2026-09-07", 1, .monday),
        // Cairo: Thursday 2026-10-29 has 25 hours; its start + 24 h is still Thursday (23:00 again).
        Change("Africa/Cairo", "2026-10-05", "2026-10-28T21:00:00Z", "2026-10-29", "2026-10-30", 3, .friday),
        Change("Africa/Cairo", "2026-10-05", "2026-10-29T20:59:59Z", "2026-10-29", "2026-10-30", 3, .friday),
        Change("Africa/Cairo", "2026-10-05", "2026-10-29T21:00:00Z", "2026-10-29", "2026-10-30", 3, .friday),
        Change("Africa/Cairo", "2026-10-05", "2026-10-29T21:59:59Z", "2026-10-29", "2026-10-30", 3, .friday),
        Change("Africa/Cairo", "2026-10-05", "2026-10-29T22:00:00Z", "2026-10-30", "2026-10-31", 3, .saturday),
        // Havana: Sunday 2026-11-01 has two midnights (00:59:59 → 00:00).
        Change("America/Havana", "2026-10-05", "2026-11-01T03:59:59Z", "2026-10-31", "2026-11-01", 3, .sunday),
        Change("America/Havana", "2026-10-05", "2026-11-01T04:00:00Z", "2026-11-01", "2026-11-02", 4, .monday),
        Change("America/Havana", "2026-10-05", "2026-11-01T05:00:00Z", "2026-11-01", "2026-11-02", 4, .monday),
        Change("America/Havana", "2026-10-05", "2026-11-01T05:30:00Z", "2026-11-01", "2026-11-02", 4, .monday),
        // Havana: midnight of Sunday 2026-03-08 is skipped.
        Change("America/Havana", "2026-03-02", "2026-03-08T04:59:59Z", "2026-03-07", "2026-03-08", 0, .sunday),
        Change("America/Havana", "2026-03-02", "2026-03-08T05:00:00Z", "2026-03-08", "2026-03-09", 1, .monday),
        // Nuuk: Saturday 2026-03-28 ends at 23:00 (22:59:59 → Sunday 00:00), a 23-hour day.
        Change("America/Nuuk", "2026-03-02", "2026-03-29T00:59:59Z", "2026-03-28", "2026-03-29", 3, .sunday),
        Change("America/Nuuk", "2026-03-02", "2026-03-29T01:00:00Z", "2026-03-29", "2026-03-30", 4, .monday)
    ]

    /// Six moments of every day from three days before the block to three days after it: a second
    /// before the day starts, its start, a second in, 23 and 24 hours in (the same day or the next,
    /// depending on its length), and noon.
    static func moments(around start: CivilDate, weekCount: Int, in zone: TimeZone) throws -> [Date] {
        let seconds: [TimeInterval] = [-1, 0, 1, 82800, 86399, 86400]
        var moments: [Date] = []
        for offset in -3 ..< 7 * weekCount + 3 {
            let day = try #require(start.adding(days: offset))
            let first = try Support.startOfDay(day, in: zone)
            moments += seconds.map { first.addingTimeInterval($0) }
            try moments.append(Support.moment(day, in: zone))
        }
        return moments
    }

    /// Asserts the product against both references for every moment of `moments(around:…)`.
    static func check(_ program: Program, _ weeks: WeekCalendar, in zone: TimeZone, _ label: String) throws {
        let reference = try SessionReference(arithmeticOf: program, start: weeks.startDate, in: zone)
        let walked = try SessionReference(walking: program, with: weeks, in: zone)
        #expect(reference.sessions == walked.sessions, "the two references disagree: \(label)")
        for moment in try moments(around: weeks.startDate, weekCount: program.weeks.count, in: zone) {
            let next = weeks.nextScheduledDay(after: moment, in: program)
            #expect(try next == reference.next(after: moment), "\(label), after \(moment)")
        }
    }
}

extension NextScheduledDayMatrixAdversarialTests.Change {
    init(
        _ zone: String,
        _ start: String,
        _ instant: String,
        _ today: String,
        _ next: String,
        _ weekIndex: Int,
        _ weekday: Weekday
    ) {
        self.init(
            zone: zone, start: start, instant: instant, today: today, next: next, weekIndex: weekIndex, weekday: weekday
        )
    }
}

extension NextScheduledDayMatrixAdversarialTests {
    @Test(
        "Whatever weekday the block begins on and whatever day the stats week starts, the seed's answers hold.",
        arguments: 0 ..< 7
    )
    func nextScheduledDay_everyStartWeekdayAndWeekStart_seedSchedule(shift: Int) throws {
        let start = try #require(Support.seedStart.adding(days: shift))
        let program = try Support.seedProgram(start: start)
        #expect(start.weekday == Weekday(rawValue: shift + 1))
        for weekStart in Weekday.allCases {
            let weeks = Support.weeks(start: start, weekStart: weekStart)
            try Self.check(program, weeks, in: Fixtures.utc, "block from \(start), weeks start on \(weekStart)")
        }
    }

    @Test(
        "A block that trains every day answers the next day, with that day's own week and template.",
        arguments: 0 ..< 7
    )
    func nextScheduledDay_everyStartWeekdayAndWeekStart_everyDaySchedule(shift: Int) throws {
        let start = try #require(Support.seedStart.adding(days: shift))
        let program = try Support.everyDayProgram(start: start)
        let zone = try Fixtures.zone("America/Chicago")
        for weekStart in Weekday.allCases {
            let weeks = Support.weeks(start: start, weekStart: weekStart, zone: zone)
            try Self.check(program, weeks, in: zone, "block from \(start), weeks start on \(weekStart)")
        }
    }

    @Test(
        "Around every midnight of blocks that hold each zone's 2026 clock changes, a day is never skipped or repeated.",
        arguments: zones
    )
    func nextScheduledDay_aroundEveryMidnight_inZonesThatChangeAtMidnight(identifier: String) throws {
        let zone = try Fixtures.zone(identifier)
        for (number, base) in Self.bases.enumerated() {
            for shift in 0 ..< 7 {
                let start = try #require(base.adding(days: shift))
                let weekStart = try #require(Weekday(rawValue: (shift + number * 3) % 7 + 1))
                let weeks = Support.weeks(start: start, weekStart: weekStart, zone: zone)
                try Self.check(Support.everyDayProgram(start: start), weeks, in: zone, "\(identifier) from \(start)")
            }
        }
    }

    @Test("Skipped midnights, a second midnight, and 23- and 25-hour days, by hand.", arguments: changes)
    func nextScheduledDay_atAClockChange_matchesTheHandComputedDay(change: Change) throws {
        let zone = try Fixtures.zone(change.zone)
        let start = try #require(CivilDate(iso8601: change.start))
        let instant = try Support.instant(change.instant)
        // The zone's rule, confirmed with Foundation before the product is asked.
        try #require(try Support.civilDay(of: instant, in: zone) == CivilDate(iso8601: change.today))
        let expected = try ScheduledDay(
            date: #require(CivilDate(iso8601: change.next)),
            weekIndex: change.weekIndex,
            dayTemplateID: Support.everyDayTemplate(week: change.weekIndex, change.weekday)
        )
        let program = try Support.everyDayProgram(start: start)
        for weekStart in Weekday.allCases {
            let weeks = Support.weeks(start: start, weekStart: weekStart, zone: zone)
            #expect(weeks.nextScheduledDay(after: instant, in: program) == expected, "weeks start on \(weekStart)")
        }
    }

    @Test("Apia had no Friday 2011-12-30: the days either side of the gap still follow its calendar.")
    func nextScheduledDay_acrossADayTheZoneSkipped_keepsToTheCalendar() throws {
        let zone = try Fixtures.zone("Pacific/Apia")
        let start = Fixtures.civil(2011, 12, 26)
        let program = try Support.everyDayProgram(start: start, weekCount: 2)
        let weeks = Support.weeks(start: start, zone: zone)
        let thursday = try Support.moment(Fixtures.civil(2011, 12, 29), 23, 59, 59, in: zone)
        // The second after Thursday 23:59:59 is Saturday 00:00.
        let saturday = thursday.addingTimeInterval(1)
        try #require(try Support.civilDay(of: saturday, in: zone) == Fixtures.civil(2011, 12, 31))
        let sunday = ScheduledDay(
            date: Fixtures.civil(2012, 1, 1), weekIndex: 0, dayTemplateID: Support.everyDayTemplate(week: 0, .sunday)
        )
        #expect(weeks.nextScheduledDay(after: saturday, in: program) == sunday)
        // Whether Thursday's answer is the Friday that never came or the Saturday is not specified
        // (finding F9-S2-3): it is one of the two, and it is consistent with itself.
        let next = try #require(weeks.nextScheduledDay(after: thursday, in: program))
        #expect([Fixtures.civil(2011, 12, 30), Fixtures.civil(2011, 12, 31)].contains(next.date))
        #expect(next.weekIndex == 0)
        #expect(next.weekday == next.date.weekday)
        #expect(next.dayTemplateID == Support.everyDayTemplate(week: 0, next.weekday))
    }
}
