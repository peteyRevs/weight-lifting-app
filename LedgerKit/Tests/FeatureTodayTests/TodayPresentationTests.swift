@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3: `TodayPresentation.make(_:)`, on the brief's worked examples (the seed program begun on Monday
/// 2026-09-14) and on what the brief leaves open. This file holds the header and the rows of the card's decision
/// table; each part of the model has its own extension file.
@Suite("TodayPresentation", .tags(.feature))
nonisolated struct TodayPresentationTests {
    /// One row of the decision table: a moment in the seed program's block, and what the calendar alone decides.
    struct CalendarRow: Sendable, CustomStringConvertible {
        let description: String
        let now: Date
        let card: String
        let title: String
    }

    static let calendarRows = [
        CalendarRow(
            description: "the day before the block begins",
            now: Fixtures.date(2026, 9, 13, hour: 12),
            card: "restDay",
            title: "Rest day"
        ),
        CalendarRow(
            description: "the block's first minute",
            now: Fixtures.date(2026, 9, 14),
            card: "upNext",
            title: "Upper A"
        ),
        CalendarRow(
            description: "Tuesday of week 1",
            now: Fixtures.date(2026, 9, 15, hour: 9),
            card: "restDay",
            title: "Rest day"
        ),
        CalendarRow(description: "Wednesday of week 1", now: Fixtures.now, card: "upNext", title: "Lower A"),
        CalendarRow(
            description: "the last minute of the block",
            now: Fixtures.date(2026, 11, 8, hour: 23, minute: 59),
            card: "restDay",
            title: "Rest day"
        ),
        CalendarRow(
            description: "the first minute after the block",
            now: Fixtures.date(2026, 11, 9),
            card: "blockComplete",
            title: "Today"
        )
    ]

    @Test("The header reads the date in words and today's day name before the dash (criterion 1)")
    func header_weekOneWednesday_readsTheDateAndLowerA() throws {
        let header = try TodayPresentation.make(TodayFixtures.input()).header
        #expect(header.date == "Wednesday, September 16")
        #expect(header.title == "Lower A")
        #expect(header.settings == TodayModel.Action(title: "Settings", route: .settings))
    }

    @Test("The date follows the injected locale, calendar and time zone, not the device's")
    func header_otherLocaleAndZone_formatsWithThem() throws {
        var input = try TodayFixtures.input()
        input.locale = Locale(identifier: "de_DE")
        #expect(TodayPresentation.make(input).header.date == "Mittwoch, 16. September")
        // 05:20 UTC on Wednesday is still Tuesday evening in Los Angeles: a rest day there.
        input.locale = Fixtures.locale
        input.calendar = try TodayFixtures.calendar(in: "America/Los_Angeles")
        let header = TodayPresentation.make(input).header
        #expect(header.date == "Tuesday, September 15")
        #expect(header.title == "Rest day")
    }

    @Test("With no workout in play, the calendar decides the card and the title", arguments: calendarRows)
    func card_byTheCalendar_followsTheDecisionTable(row: CalendarRow) throws {
        let model = try TodayPresentation.make(TodayFixtures.input(now: row.now))
        #expect(model.card.kind == row.card)
        #expect(model.header.title == row.title)
    }

    @Test("With no program the card says so, the title is Today and the button sets one up (criterion 8)")
    func noProgram_cardAndTitle() throws {
        let model = try TodayPresentation.make(TodayFixtures.input(program: nil))
        #expect(model.header.title == "Today")
        #expect(model.header.date == "Wednesday, September 16")
        let card = try #require(model.card.message)
        #expect(model.card.kind == "noProgram")
        #expect(card.title == "No program yet")
        #expect(card.body == "Set up a program to see your next session here.")
        #expect(card.action == TodayModel.Action(title: "Set up program", route: .setUpProgram))
    }

    @Test("Past the last week the block is complete, and the rest of the screen is still filled (criterion 7)")
    func blockComplete_whenWeekIndexPastTheBlock() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 11, 11, hour: 9))
        let monday = try TodayFixtures.workout(1, pounds: 8120, startedAt: Fixtures.date(2026, 11, 9, hour: 7))
        input.weekWorkouts = [monday]
        input.recentWorkouts = [monday]
        let model = TodayPresentation.make(input)
        let card = try #require(model.card.message)
        #expect(model.card.kind == "blockComplete")
        #expect(model.header.title == "Today")
        #expect(card.title == "Block complete")
        #expect(card.body == "8 weeks done. Start the next block from Program.")
        #expect(card.action == TodayModel.Action(title: "Open Program", route: .openProgram))
        // Nothing is planned after the block; what was trained still shows.
        #expect(model.weekStrip.marks == "D-T----")
        #expect(model.stats.sessions.value == "1")
        #expect(model.stats.sessions.unit == "/0")
        #expect(model.stats.volume.value == "8.1")
        #expect(model.recent.rows.map(\.meta) == ["Mon · 58 min · 8,120 lb"])
    }

    @Test("A program whose current week is missing is a rest day, and a scheduled day it does not hold too")
    func card_programEditedAfterValidation_isARestDay() throws {
        var gap = try TodayFixtures.program()
        gap.weeks.removeFirst()
        #expect(try TodayPresentation.make(TodayFixtures.input(program: gap)).card.kind == "restDay")
        var dangling = try TodayFixtures.program()
        dangling.days.remove(at: TodayFixtures.DayIndex.lowerA)
        let model = try TodayPresentation.make(TodayFixtures.input(program: dangling))
        #expect(model.card.kind == "restDay")
        #expect(model.header.title == "Rest day")
    }

    @Test("An input with nothing but settings, a moment, a calendar and a locale gives the empty Today")
    func make_emptyInput_isTheEmptyToday() {
        let input = TodayInput(
            settings: .default,
            now: Fixtures.now,
            calendar: Fixtures.calendar,
            locale: Fixtures.locale
        )
        let model = TodayPresentation.make(input)
        #expect(model.card.kind == "noProgram")
        #expect(model.weekStrip.marks == "--T----")
        #expect(model.recent.rows.isEmpty)
        #expect(model.stats.volume.delta == nil)
    }

    @Test("The same input gives the same model")
    func make_sameInput_givesTheSameModel() throws {
        let input = try TodayFixtures.input()
        let isSame = TodayPresentation.make(input) == TodayPresentation.make(input)
        #expect(isSame)
    }

    @Test(
        "A moment with no calendar date gives a model all the same: nothing traps",
        arguments: [
            Date.distantPast, .distantFuture,
            Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: -.infinity),
            Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: 1e15)
        ]
    )
    func make_momentOutsideTheCalendar_doesNotTrap(now: Date) throws {
        let program = try TodayFixtures.program()
        for calendar in try [Fixtures.calendar, TodayFixtures.calendar(in: "Pacific/Pago_Pago")] {
            for candidate in [program, nil] {
                var input = try TodayFixtures.input(program: candidate, now: now)
                input.calendar = calendar
                input.weekWorkouts = try [TodayFixtures.workout(1, pounds: 100, startedAt: now)]
                input.recentWorkouts = input.weekWorkouts
                let model = TodayPresentation.make(input)
                #expect(model.weekStrip.count <= 7)
                #expect(model.recent.rows.count == 1)
            }
        }
    }
}
