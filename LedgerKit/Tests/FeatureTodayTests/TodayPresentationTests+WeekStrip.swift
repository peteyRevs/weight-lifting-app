@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// The week strip (specification criterion 2; the body's criteria 1 and 11).
nonisolated extension TodayPresentationTests {
    /// A week that holds a day of 23 or 25 hours, in the zone whose clocks change at midnight.
    struct ZoneWeek: Sendable, CustomStringConvertible {
        let zone: String
        /// The Monday the week begins on.
        let monday: [Int]
        let dates: [String]

        var description: String {
            "\(zone), the week of \(monday)"
        }
    }

    static let zoneWeeks = [
        // Midnight is skipped on Sunday 6 September: the day begins at 01:00.
        ZoneWeek(
            zone: "America/Santiago",
            monday: [2026, 8, 31],
            dates: ["31", "1", "2", "3", "4", "5", "6"]
        ),
        // Midnight is skipped on Friday 24 April.
        ZoneWeek(
            zone: "Africa/Cairo",
            monday: [2026, 4, 20],
            dates: ["20", "21", "22", "23", "24", "25", "26"]
        ),
        // Sunday 1 November has 25 hours: midnight to 01:00 comes twice.
        ZoneWeek(
            zone: "America/Havana",
            monday: [2026, 10, 26],
            dates: ["26", "27", "28", "29", "30", "31", "1"]
        ),
        // The far ends of the day line.
        ZoneWeek(
            zone: "Pacific/Kiritimati",
            monday: [2026, 9, 14],
            dates: ["14", "15", "16", "17", "18", "19", "20"]
        ),
        ZoneWeek(
            zone: "Pacific/Pago_Pago",
            monday: [2026, 9, 14],
            dates: ["14", "15", "16", "17", "18", "19", "20"]
        )
    ]

    @Test("Week 1's Wednesday: Monday to Sunday, today and the three sessions still planned (criterion 1)")
    func weekStrip_weekOneWednesday_isMondayToSunday() throws {
        let strip = try TodayPresentation.make(TodayFixtures.input()).weekStrip
        #expect(strip.map(\.weekday).joined() == "MTWTFSS")
        #expect(strip.map(\.date) == ["14", "15", "16", "17", "18", "19", "20"])
        #expect(strip.marks == "P-T-PP-")
        #expect(strip.map(\.accessibilitySummary) == [
            "Monday, September 14", "Tuesday, September 15", "Wednesday, September 16", "Thursday, September 17",
            "Friday, September 18", "Saturday, September 19", "Sunday, September 20"
        ])
    }

    @Test("A day's mark is the first that applies of done, today, planned and rest")
    func weekStrip_marksDoneTodayPlannedAndRest() throws {
        let program = try TodayFixtures.program()
        // Monday's session was done, and so was an off-schedule one on Tuesday, a rest day.
        let monday = try TodayFixtures.workout(1, pounds: 100, startedAt: Fixtures.date(2026, 9, 14, hour: 7))
        let tuesday = try TodayFixtures.workout(2, pounds: 100, startedAt: Fixtures.date(2026, 9, 15, hour: 7))
        #expect(try Self.model(program, now: Fixtures.now, weekWorkouts: [monday]).weekStrip.marks == "D-T-PP-")
        #expect(try Self.model(program, now: Fixtures.now, weekWorkouts: [tuesday, monday]).weekStrip
            .marks == "DDT-PP-")
        // On Thursday, a rest day, today is marked and Wednesday's missed session still reads planned.
        let thursday = Fixtures.date(2026, 9, 17, hour: 9)
        #expect(try Self.model(program, now: thursday, weekWorkouts: [monday]).weekStrip.marks == "D-PTPP-")
    }

    @Test("Once today is trained its mark is done, and its spoken label says it is today")
    func weekStrip_todayDone_saysTodayInItsLabel() throws {
        let program = try TodayFixtures.program()
        let today = try TodayFixtures.workout(1, pounds: 100, startedAt: Fixtures.date(2026, 9, 16, hour: 4))
        let monday = try TodayFixtures.workout(2, pounds: 100, startedAt: Fixtures.date(2026, 9, 14, hour: 7))
        let strip = try Self.model(program, now: Fixtures.now, weekWorkouts: [today, monday]).weekStrip
        #expect(strip.marks == "D-D-PP-")
        #expect(strip[2].accessibilitySummary == "Today, Wednesday, September 16")
        #expect(strip[0].accessibilitySummary == "Monday, September 14")
        // Not yet trained, the mark itself says "Today": the label is the date alone.
        let untrained = try Self.model(program, now: Fixtures.now, weekWorkouts: [monday]).weekStrip
        #expect(untrained[2].accessibilitySummary == "Wednesday, September 16")
    }

    @Test("With a Sunday week start the strip runs Sunday to Saturday (criterion 11)")
    func weekStartSunday_stripRunsSundayToSaturday() throws {
        var settings = Fixtures.settingsLb
        settings.weekStart = .sunday
        let input = try TodayFixtures.input(program: TodayFixtures.program(), settings: settings)
        let strip = TodayPresentation.make(input).weekStrip
        #expect(strip.map(\.weekday).joined() == "SMTWTFS")
        #expect(strip.map(\.date) == ["13", "14", "15", "16", "17", "18", "19"])
        // Sunday the 13th is before the block: nothing is planned on it.
        #expect(strip.marks == "-P-T-PP")
    }

    @Test("Every week start begins the strip on that weekday, and the strip holds today", arguments: Weekday.allCases)
    func weekStrip_everyWeekStart_beginsOnItAndHoldsToday(weekStart: Weekday) throws {
        var settings = Fixtures.settingsLb
        settings.weekStart = weekStart
        let strip = try TodayPresentation.make(TodayFixtures.input(program: nil, settings: settings)).weekStrip
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        #expect(strip.count == 7)
        #expect(strip.first?.accessibilitySummary.hasPrefix(names[weekStart.rawValue - 1]) == true)
        #expect(strip.map(\.mark).count { $0 == .today } == 1)
        #expect(strip.contains { $0.mark == .today && $0.date == "16" })
    }

    @Test("A strip that straddles two program weeks reads each day from its own program week")
    func misalignedWeekStart_stripLooksUpEachDate() throws {
        // The block begins on a Wednesday, the stats week on Monday: Monday and Tuesday of the strip are the
        // last days of program week 1, the rest the first days of week 2.
        var program = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 16))
        let upperA = program.days[TodayFixtures.DayIndex.upperA].id
        program.weeks[0].schedule = [.monday: upperA]
        program.weeks[1].schedule = [.friday: upperA]
        let input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 21, hour: 9))
        let model = TodayPresentation.make(input)
        #expect(model.weekStrip.map(\.date) == ["21", "22", "23", "24", "25", "26", "27"])
        #expect(model.weekStrip.marks == "T---P--")
        #expect(model.stats.sessions.unit == "/2")
        // Today is the Monday of program week 1, so the card is that week's.
        #expect(model.card.upNext?.meta == "Week 1 of 8 · ~39 min")
        // On Wednesday the block is in its week 2, and the strip is the same seven days.
        let wednesday = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 23, hour: 9))
        let later = TodayPresentation.make(wednesday)
        #expect(later.weekStrip.marks == "P-T-P--")
        #expect(later.card.restDay?.body == "Nothing scheduled for Wednesday in week 2. Next up is Friday.")
    }

    @Test("Where the clocks change at midnight the strip still holds seven consecutive days", arguments: zoneWeeks)
    func weekStrip_dayOf23Or25Hours_isOneDay(week: ZoneWeek) throws {
        let calendar = try TodayFixtures.calendar(in: week.zone)
        let start = try TodayFixtures.civil(week.monday[0], week.monday[1], week.monday[2])
        let program = try TodayFixtures.program(startingOn: start)
        // Every day of the week, early and late: the strip is the same week, and today is that day.
        for offset in 0 ..< 7 {
            let day = try #require(start.adding(days: offset))
            for hour in [1, 12, 23] {
                var input = try TodayFixtures.input(
                    program: program,
                    now: Fixtures.date(day.year, day.month, day.day, hour: hour, minute: 30, in: calendar.timeZone)
                )
                input.calendar = calendar
                let strip = TodayPresentation.make(input).weekStrip
                let context: Comment = "\(day) at \(hour):30"
                #expect(strip.map(\.date) == week.dates, context)
                #expect(strip.map(\.weekday).joined() == "MTWTFSS", context)
                #expect(strip.firstIndex { $0.mark == .today } == offset, context)
            }
        }
    }

    @Test("A workout is marked on the day it started in the calendar's zone, around a skipped midnight too")
    func weekStrip_workoutAroundASkippedMidnight_marksItsStartDay() throws {
        // In Santiago, Saturday 5 September 23:59 is followed by Sunday 6 September 01:00.
        let calendar = try TodayFixtures.calendar(in: "America/Santiago")
        let zone = calendar.timeZone
        let program = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 8, 31))
        var input = try TodayFixtures.input(
            program: program,
            now: Fixtures.date(2026, 9, 6, hour: 1, minute: 30, in: zone)
        )
        input.calendar = calendar
        input.weekWorkouts = try [
            TodayFixtures.workout(1, pounds: 100, startedAt: Fixtures.date(2026, 9, 5, hour: 23, minute: 30, in: zone))
        ]
        let model = TodayPresentation.make(input)
        #expect(model.weekStrip.marks == "P-P-PDT")
        #expect(model.header.date == "Sunday, September 6")
        // The same instants read in UTC are both on Sunday the 6th: the zone decides the day.
        input.calendar = Fixtures.calendar
        #expect(TodayPresentation.make(input).weekStrip.marks == "P-P-PPD")
    }

    @Test("With no program nothing is planned: the strip marks today and what was trained (criterion 8)")
    func noProgram_stripHasNoPlannedMarks() throws {
        var input = try TodayFixtures.input(program: nil)
        #expect(TodayPresentation.make(input).weekStrip.marks == "--T----")
        input.weekWorkouts = try [TodayFixtures.workout(1, pounds: 100, startedAt: Fixtures.date(2026, 9, 14, hour: 7))]
        #expect(TodayPresentation.make(input).weekStrip.marks == "D-T----")
    }
}
