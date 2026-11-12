import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 1 over seeded random blocks: any length, start day, week start, zone and
/// schedule (empty weeks, deloads, a calendar that starts on another day than the program says).
/// The expected answer is `SessionReference`'s; the day-by-day walk of the brief is asserted too.
@Suite("WeekCalendar.nextScheduledDay properties (adversarial, F09 S2)", .tags(.domain, .property))
struct NextScheduledDayPropertyAdversarialTests {
    typealias Support = ScheduleAdversarial

    static let zones = NextScheduledDayMatrixAdversarialTests.zones + ["America/Chicago", "Asia/Tokyo", "Asia/Kolkata"]

    struct Scenario {
        let program: Program
        let weeks: WeekCalendar
        let zone: TimeZone
        let moments: [Date]
    }

    /// A random valid program, a calendar for it, and 40 moments from 15 days before it to 15 after.
    static func scenario(using generator: inout SeededGenerator) throws -> Scenario {
        let zone = try Fixtures.zone(#require(zones.randomElement(using: &generator)))
        let origin = Fixtures.civil(2026, 1, 1)
        let programStart = try #require(origin.adding(days: Int.random(in: 0 ..< 730, using: &generator)))
        let program = try randomProgram(start: programStart, using: &generator)
        // One block in four is read with a calendar that starts on another day than `program.startDate`:
        // the calendar's start is the one `scheduledDay(on:in:)` counts from.
        let drift = Int.random(in: 0 ..< 4, using: &generator) == 0 ? Int.random(in: -10 ... 10, using: &generator) : 0
        let start = try #require(programStart.adding(days: drift))
        let weekStart = try #require(Weekday.allCases.randomElement(using: &generator))
        let weeks = Support.weeks(start: start, weekStart: weekStart, zone: zone)
        var moments: [Date] = []
        for index in 0 ..< 40 {
            let offset = Int.random(in: -15 ..< 7 * program.weeks.count + 15, using: &generator)
            let first = try Support.startOfDay(#require(start.adding(days: offset)), in: zone)
            let boundary: [TimeInterval] = [-1, 0, 1, 86399, 86400]
            let random = TimeInterval(Int.random(in: 0 ..< 86400, using: &generator))
            let seconds = try index < 10 ? #require(boundary.randomElement(using: &generator)) : random
            moments.append(first.addingTimeInterval(seconds))
        }
        return Scenario(program: program, weeks: weeks, zone: zone, moments: moments)
    }

    static func randomProgram(start: CivilDate, using generator: inout SeededGenerator) throws -> Program {
        let days = (0 ..< Int.random(in: 1 ... 5, using: &generator)).map {
            Support.template(9000 + $0, "Day \($0)", "D\($0)")
        }
        let sessionsPerWeek = try #require([0, 1, 3, 6, 7].randomElement(using: &generator))
        let weeks = try (0 ..< Int.random(in: 2 ... 10, using: &generator)).map { index -> Week in
            var schedule: [Weekday: DayTemplateID] = [:]
            let isEmpty = Int.random(in: 0 ..< 5, using: &generator) == 0
            for weekday in Weekday.allCases where !isEmpty {
                if Int.random(in: 0 ..< 7, using: &generator) < sessionsPerWeek {
                    schedule[weekday] = try #require(days.randomElement(using: &generator)).id
                }
            }
            return Support.week(index, deload: Bool.random(using: &generator), schedule)
        }
        return try Support.program(start: start, weeks: weeks.shuffled(using: &generator), days: days)
    }

    /// The brief's walk, one day at a time with `scheduledDay(on:in:)`: `next` is strictly later than
    /// the moment's day, inside the block, scheduled as it says, and no earlier day is scheduled.
    static func expectEarliestLaterDay(_ next: ScheduledDay?, after moment: Date, in scenario: Scenario) throws {
        let weeks = scenario.weeks
        let program = scenario.program
        let today = try Support.civilDay(of: moment, in: scenario.zone)
        let last = try #require(weeks.startDate.adding(days: 7 * program.weeks.count - 1))
        if let next {
            let noon = try Support.moment(next.date, in: scenario.zone)
            #expect(next.date > today)
            #expect(next.date >= weeks.startDate && next.date <= last)
            #expect(weeks.scheduledDay(on: noon, in: program) == next.dayTemplateID)
            #expect(weeks.weekIndex(for: noon) == next.weekIndex)
            #expect(next.weekday == weeks.weekday(of: noon))
        }
        var day = try #require(max(today, weeks.startDate.adding(days: -1) ?? today).adding(days: 1))
        while day <= last, day != next?.date {
            let noon = try Support.moment(day, in: scenario.zone)
            #expect(
                weeks.scheduledDay(on: noon, in: program) == nil,
                "\(day) is an earlier session than \(next as Any)"
            )
            day = try #require(day.adding(days: 1))
        }
    }
}

extension NextScheduledDayPropertyAdversarialTests {
    @Test("For random blocks and moments the answer is the reference's.", arguments: PropertySeed.all)
    func nextScheduledDay_randomBlocksAndMoments_matchTheReference(seed: PropertySeed) throws {
        var generator = seed.generator
        let scenario = try Self.scenario(using: &generator)
        let reference = try SessionReference(
            arithmeticOf: scenario.program, start: scenario.weeks.startDate, in: scenario.zone
        )
        let walked = try SessionReference(walking: scenario.program, with: scenario.weeks, in: scenario.zone)
        #expect(reference.sessions == walked.sessions, "the two references disagree (\(seed))")
        for moment in scenario.moments {
            let next = scenario.weeks.nextScheduledDay(after: moment, in: scenario.program)
            #expect(
                try next == reference.next(after: moment),
                "\(seed), after \(moment) in \(scenario.zone.identifier)"
            )
        }
    }

    @Test(
        "The answer is strictly later than the moment's day and no earlier day is scheduled.",
        arguments: PropertySeed.all
    )
    func nextScheduledDay_randomBlocksAndMoments_isTheEarliestLaterSession(seed: PropertySeed) throws {
        var generator = seed.generator
        let scenario = try Self.scenario(using: &generator)
        for moment in scenario.moments {
            let next = scenario.weeks.nextScheduledDay(after: moment, in: scenario.program)
            try Self.expectEarliestLaterDay(next, after: moment, in: scenario)
        }
    }

    @Test(
        "Asking again from each answer visits every session of the block once, in order, then ends.",
        arguments: PropertySeed.all
    )
    func nextScheduledDay_chainedFromBeforeTheBlock_visitsEverySessionOnce(seed: PropertySeed) throws {
        var generator = seed.generator
        let scenario = try Self.scenario(using: &generator)
        let reference = try SessionReference(
            arithmeticOf: scenario.program, start: scenario.weeks.startDate, in: scenario.zone
        )
        let before = try #require(scenario.weeks.startDate.adding(days: -40))
        var cursor = try Support.moment(before, in: scenario.zone)
        var visited: [ScheduledDay] = []
        while let next = scenario.weeks.nextScheduledDay(after: cursor, in: scenario.program) {
            visited.append(next)
            try #require(visited.count <= reference.sessions.count, "the chain does not end (\(seed))")
            cursor = try Self.lastSecond(of: next.date, in: scenario.zone)
        }
        let isEverySessionOnce = visited == reference.sessions
        let differs = zip(visited, reference.sessions).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(visited.count, reference.sessions.count)
        #expect(
            isEverySessionOnce,
            "\(seed): \(visited.count) of \(reference.sessions.count) sessions; first difference at \(differs)"
        )
    }

    /// The last second of `day` in `zone`: one second before the next day starts. 23:59:59 is not always
    /// on `day`: America/Nuuk springs forward from 23:00 on a Saturday, so Foundation reads its 23:59:59
    /// as the Sunday's 00:59:59, and a chain asked from there skipped that Sunday (seeds 10365988 and
    /// 12955501 of the walk above, 2026-11-11).
    static func lastSecond(of day: CivilDate, in zone: TimeZone) throws -> Date {
        try Support.startOfDay(#require(day.adding(days: 1)), in: zone).addingTimeInterval(-1)
    }

    @Test("Asked at the last second of a Saturday whose clocks skip 23:00–24:00, the answer is that Sunday")
    func nextScheduledDay_lastSecondBeforeASpringForwardMidnight_answersTheNextDay() throws {
        let zone = try Fixtures.zone("America/Nuuk")
        let saturday = Fixtures.civil(2026, 3, 28)
        let sunday = Fixtures.civil(2026, 3, 29)
        let program = try Support.program(
            start: Fixtures.civil(2026, 3, 23),
            weeks: [Support.week(0, [.saturday: Support.upperA.id, .sunday: Support.lowerA.id]), Support.week(1, [:])],
            days: [Support.upperA, Support.lowerA]
        )
        let weeks = Support.weeks(start: program.startDate, weekStart: .monday, zone: zone)
        let lastSecond = try Self.lastSecond(of: saturday, in: zone)
        #expect(try Support.civilDay(of: lastSecond, in: zone) == saturday)
        #expect(
            weeks.nextScheduledDay(after: lastSecond, in: program)
                == ScheduledDay(date: sunday, weekIndex: 0, dayTemplateID: Support.lowerA.id)
        )
        // Why the walk above asks from `lastSecond(of:in:)`: Saturday's 23:59:59 is already Sunday there.
        let elevenFiftyNine = try Support.moment(saturday, 23, 59, 59, in: zone)
        try #require(
            Support.civilDay(of: elevenFiftyNine, in: zone) == sunday,
            "precondition: this tzdata springs America/Nuuk forward from 23:00 on 2026-03-28"
        )
    }

    @Test("A later moment never gets an earlier answer.", arguments: PropertySeed.all)
    func nextScheduledDay_laterMoment_neverAnswersEarlier(seed: PropertySeed) throws {
        var generator = seed.generator
        let scenario = try Self.scenario(using: &generator)
        let answers = scenario.moments.sorted().map {
            scenario.weeks.nextScheduledDay(after: $0, in: scenario.program)
        }
        for (earlier, later) in zip(answers, answers.dropFirst()) {
            guard let earlier else {
                #expect(later == nil, "\(seed): a session reappears after the block had none left")
                continue
            }
            if let later {
                #expect(earlier.date <= later.date, "\(seed)")
            }
        }
    }
}
