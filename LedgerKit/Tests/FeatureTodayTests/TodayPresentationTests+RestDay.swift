@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The Rest-day card and its off-schedule list (specification criterion 6; the body's criterion 5).
nonisolated extension TodayPresentationTests {
    /// The rest-day card of `program` at `now`.
    static func restDay(_ program: Program, now: Date) throws -> TodayModel.RestDay {
        try #require(TodayPresentation.make(TodayFixtures.input(program: program, now: now)).card.restDay)
    }

    @Test("A Saturday with nothing scheduled points to next Monday, and offers the week's edit (criterion 5)")
    func restDay_nextUp_nextWeek() throws {
        var program = try TodayFixtures.program()
        program.weeks[0].schedule[.saturday] = nil
        let card = try Self.restDay(program, now: Fixtures.date(2026, 9, 19, hour: 10))
        #expect(card.eyebrow == "SCHEDULED REST")
        #expect(card.title == "No session today")
        #expect(card.body == "Nothing scheduled for Saturday in week 1. Next up is next Monday.")
        let edit = TodayRoute.editWeek(program: program.id, weekIndex: 0)
        #expect(card.editWeek == TodayModel.Action(title: "Edit this week", route: edit))
        #expect(card.offSchedule.title == "Train off-schedule")
    }

    @Test("A rest day with a session later in the program week names that weekday")
    func restDay_nextUp_laterThisWeek() throws {
        let program = try TodayFixtures.program()
        let tuesday = try Self.restDay(program, now: Fixtures.date(2026, 9, 15, hour: 10))
        #expect(tuesday.body == "Nothing scheduled for Tuesday in week 1. Next up is Wednesday.")
        // Week 3: the edit and the body speak of the week the day is in.
        let thursday = try Self.restDay(program, now: Fixtures.date(2026, 10, 1, hour: 10))
        #expect(thursday.body == "Nothing scheduled for Thursday in week 3. Next up is Friday.")
        #expect(thursday.editWeek.route == .editWeek(program: program.id, weekIndex: 2))
    }

    @Test("After the block's last session the body says this is the last week")
    func restDay_lastWeekOfBlock() throws {
        let program = try TodayFixtures.program()
        // Week 8 schedules Monday, Wednesday and Friday: Saturday and Sunday have nothing after them.
        let saturday = try Self.restDay(program, now: Fixtures.date(2026, 11, 7, hour: 10))
        #expect(saturday.body == "Nothing scheduled for Saturday in week 8. This is the last week of the block.")
        // Thursday still has Friday.
        let thursday = try Self.restDay(program, now: Fixtures.date(2026, 11, 5, hour: 10))
        #expect(thursday.body == "Nothing scheduled for Thursday in week 8. Next up is Friday.")
    }

    @Test("With no session left in an earlier week than the last, the body says none are left (criterion 17)")
    func restDay_noSessionLeftBeforeTheLastWeek_saysNoneAreLeft() throws {
        var program = try TodayFixtures.program()
        for index in 2 ..< program.weeks.count {
            program.weeks[index].schedule = [:]
        }
        // Sunday of week 2: weeks 3 to 8 are empty, and week 2 is not the block's last.
        let sunday = try Self.restDay(program, now: Fixtures.date(2026, 9, 27, hour: 10))
        #expect(sunday.body == "Nothing scheduled for Sunday in week 2. No sessions are left in this block.")
        // In the empty weeks the same, until the last one, which says it is the last.
        let weekSeven = try Self.restDay(program, now: Fixtures.date(2026, 10, 28, hour: 10))
        #expect(weekSeven.body == "Nothing scheduled for Wednesday in week 7. No sessions are left in this block.")
        let weekEight = try Self.restDay(program, now: Fixtures.date(2026, 11, 2, hour: 10))
        #expect(weekEight.body == "Nothing scheduled for Monday in week 8. This is the last week of the block.")
    }

    @Test("The word next follows the seven days on screen, whichever program week the session is in (criterion 15)")
    func restDay_nextWord_followsTheStripNotTheProgramWeek() throws {
        // The week starts on Sunday and the block began on Monday 09-14: a strip runs Sunday to Saturday.
        var settings = Fixtures.settingsLb
        settings.weekStart = .sunday
        var program = try TodayFixtures.program()
        // Sunday 09-20 closes program week 1; Monday's session is in week 2 and on the strip of 09-20 to 09-26.
        var input = try TodayFixtures.input(
            program: program,
            now: Fixtures.date(2026, 9, 20, hour: 10),
            settings: settings
        )
        #expect(TodayPresentation.make(input).card.restDay?.body
            == "Nothing scheduled for Sunday in week 1. Next up is Monday.")
        // With a Monday week start the same day's strip ends on that Sunday: Monday is next week's.
        input.settings = Fixtures.settingsLb
        #expect(TodayPresentation.make(input).card.restDay?.body
            == "Nothing scheduled for Sunday in week 1. Next up is next Monday.")

        // The other way round: week 1 trains on its Sunday and not on its Saturday. On Saturday 09-19 the next
        // session is in the same program week, and off the strip of 09-13 to 09-19.
        program.weeks[0].schedule[.saturday] = nil
        program.weeks[0].schedule[.sunday] = program.days[TodayFixtures.DayIndex.lowerB].id
        input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 19, hour: 10), settings: settings)
        #expect(TodayPresentation.make(input).card.restDay?.body
            == "Nothing scheduled for Saturday in week 1. Next up is next Sunday.")
        input.settings = Fixtures.settingsLb
        #expect(TodayPresentation.make(input).card.restDay?.body
            == "Nothing scheduled for Saturday in week 1. Next up is Sunday.")
    }

    @Test("A block begun midweek: tomorrow's session reads without next though it opens the next program week")
    func restDay_blockBegunMidweek_tomorrowIsNotNext() throws {
        // The block began on Wednesday 09-16 and the week starts on Monday: Tuesday 11-03 closes program week 7,
        // and Wednesday 11-04, the next cell of the same strip, opens week 8.
        let program = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 16))
        let tuesday = try Self.restDay(program, now: Fixtures.date(2026, 11, 3, hour: 12))
        #expect(tuesday.body == "Nothing scheduled for Tuesday in week 7. Next up is Wednesday.")
        #expect(tuesday.editWeek.route == .editWeek(program: program.id, weekIndex: 6))
    }

    @Test("An empty week between today and the next session still reads next Monday")
    func restDay_emptyWeekBetween_stillSaysNextWeekday() throws {
        var program = try TodayFixtures.program()
        program.weeks[1].schedule = [:]
        // Sunday of week 1; week 2 is empty, so the next session is Monday of week 3.
        let sunday = try Self.restDay(program, now: Fixtures.date(2026, 9, 20, hour: 10))
        #expect(sunday.body == "Nothing scheduled for Sunday in week 1. Next up is next Monday.")
        // Inside the empty week, the same.
        let wednesday = try Self.restDay(program, now: Fixtures.date(2026, 9, 23, hour: 10))
        #expect(wednesday.body == "Nothing scheduled for Wednesday in week 2. Next up is next Monday.")
    }

    @Test("Before the block begins the body says when it starts, and the card is week 1's (criterion 16)")
    func restDay_beforeBlockStart_saysWhenTheBlockStarts() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 13, hour: 20))
        let model = TodayPresentation.make(input)
        let card = try #require(model.card.restDay)
        #expect(model.header.title == "Rest day")
        #expect(card.eyebrow == "SCHEDULED REST")
        #expect(card.title == "No session today")
        #expect(card.body == "Your block starts on Monday, September 14.")
        #expect(card.editWeek.route == .editWeek(program: program.id, weekIndex: 0))
        #expect(card.offSchedule.subtitle == "Pick a day from week 1.")
        #expect(card.offSchedule.days.map(\.route) == program.days.map {
            TodayRoute.startWorkout(program: program.id, weekIndex: 0, day: $0.id)
        })
        // Nothing of the week before the block is planned: the strip marks today alone.
        #expect(model.weekStrip.marks == "------T")
        // Three weeks before, the same sentence: the day is in no week of the block.
        let early = try Self.restDay(program, now: Fixtures.date(2026, 8, 24, hour: 9))
        #expect(early.body == "Your block starts on Monday, September 14.")
        // The date is written as the header writes one: in the injected locale.
        input.locale = Locale(identifier: "de_DE")
        #expect(TodayPresentation.make(input).card.restDay?.body == "Your block starts on Montag, 14. September.")
    }

    @Test("A block whose first session is not on its first day still starts on its first day")
    func restDay_beforeABlockThatOpensWithARestDay_namesTheBlocksFirstDay() throws {
        var program = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 28))
        program.weeks[0].schedule[.monday] = nil
        // Twelve days before: the tester's case, in which "Next up is Monday" named no coming Monday.
        let card = try Self.restDay(program, now: Fixtures.date(2026, 9, 16, hour: 12))
        #expect(card.body == "Your block starts on Monday, September 28.")
    }

    @Test("The off-schedule list holds every day of the program with its exercises and estimate (criterion 5)")
    func offSchedule_listsEveryDayOfTheProgram() throws {
        var program = try TodayFixtures.program()
        program.weeks[0].schedule[.saturday] = nil
        let sheet = try Self.restDay(program, now: Fixtures.date(2026, 9, 19, hour: 10)).offSchedule
        #expect(sheet.title == "Train off-schedule")
        #expect(sheet.subtitle == "Pick a day from week 1.")
        #expect(sheet.cancel == "Cancel")
        #expect(sheet.days.map(\.name) == program.days.map(\.name))
        #expect(sheet.days.map(\.detail) == [
            "5 exercises · ~39 min", "4 exercises · ~38 min", "4 exercises · ~37 min", "3 exercises · ~31 min"
        ])
        #expect(sheet.days.map(\.logged) == [nil, nil, nil, nil])
        #expect(sheet.days.map(\.route) == program.days.map {
            TodayRoute.startWorkout(program: program.id, weekIndex: 0, day: $0.id)
        })
    }

    @Test("Each day's estimate is decision #14's for the card's week: the deload week's are shorter")
    func offSchedule_deloadWeek_estimatesAreTheWeeks() throws {
        let program = try TodayFixtures.program()
        let sheet = try Self.restDay(program, now: Fixtures.date(2026, 11, 7, hour: 10)).offSchedule
        #expect(sheet.subtitle == "Pick a day from week 8.")
        let expected = try program.days.indices.map { index in
            let prescribed = try Self.prescriptions(of: program, weekIndex: 7, dayIndex: index)
            let minutes = TimeEstimate.minutes(day: program.days[index], prescriptions: prescribed)
            return "\(program.days[index].slots.count) exercises · ~\(minutes) min"
        }
        #expect(sheet.days.map(\.detail) == expected)
        #expect(sheet.days.first?.detail == "5 exercises · ~29 min")
        #expect(sheet.days.map(\.route).last == .startWorkout(
            program: program.id,
            weekIndex: 7,
            day: program.days[3].id
        ))
    }

    @Test("A day already done this program week reads Logged, whichever day it was done; another week's does not")
    func offSchedule_dayDoneThisWeek_readsLogged() throws {
        let program = try TodayFixtures.program()
        let monday = try Self.finishedSession(
            63,
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.upperA,
            startedAt: Fixtures.date(2026, 9, 14, hour: 7)
        )
        var lastWeek = try Self.finishedSession(
            64,
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.upperB,
            startedAt: Fixtures.date(2026, 9, 14, hour: 9)
        )
        lastWeek.source = TodayFixtures.source(of: program, weekIndex: 1, dayIndex: TodayFixtures.DayIndex.upperB)
        var input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 15, hour: 10))
        input.weekWorkouts = [lastWeek, monday]
        let days = try #require(TodayPresentation.make(input).card.restDay).offSchedule.days
        #expect(days.map(\.logged) == ["Logged", nil, nil, nil])
    }

    @Test("One exercise reads in the singular, and a day with a missing exercise counts the ones it can show")
    func offSchedule_exerciseCount_isTheRowsCount() throws {
        var program = try TodayFixtures.program()
        program.days[TodayFixtures.DayIndex.lowerB].slots.removeLast(2)
        var input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 15, hour: 10))
        input.exercises[Fixtures.CatalogID.romanianDeadlift] = nil
        let days = try #require(TodayPresentation.make(input).card.restDay).offSchedule.days
        #expect(days.map(\.detail) == [
            "5 exercises · ~39 min", "3 exercises · ~38 min", "4 exercises · ~37 min", "1 exercise · ~17 min"
        ])
    }

    @Test("A program that holds no week for today offers no day to pick")
    func offSchedule_weekMissing_listsNoDays() throws {
        var program = try TodayFixtures.program()
        program.weeks.removeFirst()
        let card = try Self.restDay(program, now: Fixtures.now)
        #expect(card.offSchedule.days.isEmpty)
        #expect(card.offSchedule.subtitle == "Pick a day from week 1.")
        #expect(card.body == "Nothing scheduled for Wednesday in week 1. Next up is next Monday.")
    }
}
