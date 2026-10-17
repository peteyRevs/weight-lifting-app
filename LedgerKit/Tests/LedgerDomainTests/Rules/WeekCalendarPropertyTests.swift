import Foundation
@testable import LedgerDomain
import Testing

/// Seeded checks of `WeekCalendar.nextScheduledDay(after:in:)` against a slow search that walks the
/// calendar one day at a time and asks `scheduledDay(on:in:)` about each day (F09 S2, criterion 1).
@Suite("WeekCalendar next scheduled day properties", .tags(.domain, .property))
struct WeekCalendarPropertyTests {
    /// Zones far from UTC on both sides, zones whose DST skips or repeats the hour at midnight, a
    /// half-hour DST and zones without DST.
    static let zones = [
        "UTC", "America/Los_Angeles", "America/New_York", "Europe/Berlin", "Asia/Kolkata", "Asia/Tokyo",
        "Pacific/Kiritimati", "Pacific/Pago_Pago", "Australia/Lord_Howe",
        "Africa/Cairo", "America/Santiago", "America/Havana", "Asia/Beirut"
    ]

    /// A Gregorian calendar in a random zone of `zones`.
    static func calendar(using generator: inout SeededGenerator) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try Fixtures.zone(zones.randomElement(using: &generator) ?? "UTC")
        return calendar
    }

    /// A valid block of 2 to 10 weeks that begins on any weekday between 2020 and 2029. Each week
    /// trains each weekday with its own chance (none, a few, about half or nearly all), so empty,
    /// sparse and full weeks sit next to each other; the last week is a deload.
    static func program(using generator: inout SeededGenerator) throws -> Program {
        let start = try #require(Fixtures.civil(2020, 1, 1).adding(days: Int.random(in: 0 ... 3650, using: &generator)))
        let weekCount = Int.random(in: 2 ... 10, using: &generator)
        var weeks: [Week] = []
        for index in 0 ..< weekCount {
            let density = [0, 15, 50, 90].randomElement(using: &generator) ?? 50
            var schedule: [Weekday: DayTemplateID] = [:]
            for weekday in Weekday.allCases where Int.random(in: 0 ..< 100, using: &generator) < density {
                schedule[weekday] = Fixtures.scheduleDays.randomElement(using: &generator)?.id
            }
            weeks.append(Fixtures.week(index, deload: index == weekCount - 1, schedule: schedule))
        }
        return try Program(
            id: Fixtures.programID,
            name: "Random",
            startDate: start,
            weeks: weeks,
            days: Fixtures.scheduleDays
        )
    }

    /// Edits `program.weeks` as no validated program is, but as the public `var` allows: weeks out of
    /// order, an index carried twice, a week missing, or no weeks at all.
    static func damage(_ program: inout Program, using generator: inout SeededGenerator) {
        switch Int.random(in: 0 ..< 4, using: &generator) {
        case 0:
            program.weeks.shuffle(using: &generator)
        case 1:
            let source = Int.random(in: 0 ..< program.weeks.count, using: &generator)
            let target = Int.random(in: 0 ..< program.weeks.count, using: &generator)
            program.weeks[target].index = program.weeks[source].index
        case 2:
            program.weeks.remove(at: Int.random(in: 0 ..< program.weeks.count, using: &generator))
        default:
            program.weeks = []
        }
    }

    /// A moment on a calendar day from 15 days before `start` to 15 days after the longest block (10
    /// weeks): the day's first instant, its last second, or any second of its first 23 hours. The
    /// moment and its day come from Foundation alone.
    static func moment(
        around start: CivilDate,
        in calendar: Calendar,
        using generator: inout SeededGenerator
    ) throws -> (moment: Date, day: CivilDate) {
        let day = try #require(start.adding(days: Int.random(in: -15 ... 85, using: &generator)))
        let noon = Fixtures.date(day.year, day.month, day.day, hour: 12, in: calendar.timeZone)
        let first = calendar.startOfDay(for: noon)
        switch Int.random(in: 0 ..< 4, using: &generator) {
        case 0:
            return (first, day)
        case 1:
            let nextNoon = try #require(calendar.date(byAdding: .day, value: 1, to: noon))
            return (calendar.startOfDay(for: nextNoon).addingTimeInterval(-1), day)
        default:
            return (first.addingTimeInterval(Double(Int.random(in: 0 ..< 23 * 3600, using: &generator))), day)
        }
    }

    /// The reference. From noon of the moment's own day it steps one calendar day at a time, with
    /// Foundation's calendar arithmetic, and returns the first day that `scheduledDay(on:in:)` says is
    /// scheduled. It skips days before the block and gives up once `isBlockComplete` says the block is over.
    static func slowNextScheduledDay(
        after moment: Date,
        in program: Program,
        weeks: WeekCalendar,
        calendar: Calendar
    ) throws -> ScheduledDay? {
        var parts = calendar.dateComponents([.year, .month, .day], from: moment)
        parts.hour = 12
        let today = try #require(calendar.date(from: parts))
        for offset in 1 ... 200 {
            let noon = try #require(calendar.date(byAdding: .day, value: offset, to: today))
            if weeks.isBlockComplete(program, on: noon) {
                return nil
            }
            if weeks.weekIndex(for: noon) >= 0, let template = weeks.scheduledDay(on: noon, in: program) {
                return try ScheduledDay(
                    date: #require(weeks.civilDate(of: noon)),
                    weekIndex: weeks.weekIndex(for: noon),
                    dayTemplateID: template
                )
            }
        }
        Issue.record("The reference walked 200 days without reaching the end of the block")
        return nil
    }

    /// Checks eight moments around `program`'s block against the reference, under two week starts.
    static func check(_ program: Program, using generator: inout SeededGenerator) throws {
        let calendar = try Self.calendar(using: &generator)
        let weekStarts = Weekday.allCases.shuffled(using: &generator).prefix(2)
        let weeks = weekStarts.map { WeekCalendar(startDate: program.startDate, weekStart: $0, calendar: calendar) }
        for _ in 0 ..< 8 {
            let (moment, day) = try Self.moment(around: program.startDate, in: calendar, using: &generator)
            let context: Comment = "\(calendar.timeZone.identifier), block from \(program.startDate), \(moment)"
            #expect(weeks[0].civilDate(of: moment) == day, context)
            let next = weeks[0].nextScheduledDay(after: moment, in: program)
            let expected = try Self.slowNextScheduledDay(
                after: moment,
                in: program,
                weeks: weeks[0],
                calendar: calendar
            )
            #expect(next == expected, context)
            #expect(next == weeks[1].nextScheduledDay(after: moment, in: program), context)
            #expect(next.map { $0.date > day } ?? true, context)
        }
    }
}

extension WeekCalendarPropertyTests {
    @Test(
        "The next scheduled day is the one a day-by-day search finds, in any zone and for any week start.",
        arguments: PropertySeed.all
    )
    func nextScheduledDay_matchesTheDayByDaySearch(seed: PropertySeed) throws {
        var generator = seed.generator
        let program = try Self.program(using: &generator)
        try Self.check(program, using: &generator)
    }

    @Test(
        "For weeks reordered, repeated, removed or all gone, it still ends and agrees with the day-by-day search.",
        arguments: PropertySeed.all
    )
    func nextScheduledDay_editedWeeks_matchTheDayByDaySearch(seed: PropertySeed) throws {
        var generator = seed.generator
        var program = try Self.program(using: &generator)
        Self.damage(&program, using: &generator)
        try Self.check(program, using: &generator)
    }
}
