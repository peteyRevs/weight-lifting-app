@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The notices (the brief's criterion 4 and the plan's behaviour 6): each is a final line, built here, that
/// the store shows from an action, from an error or from an edit's result.
nonisolated extension ProgramPresentationTests {
    @Test("Minus on a block of two weeks changes nothing and says a block needs at least 2 weeks")
    func removeWeek_twoWeeks_showsTheNoticeAndChangesNothing() throws {
        let program = try ProgramFixtures.program(weekCount: 2, days: [ProgramFixtures.day(1, slotCount: 2)])
        var screen = try BuilderScreen(ProgramFixtures.input(program))
        #expect(screen.model.block.removeWeek == .notice(.minimumTwoWeeks))
        try screen.tap(screen.model.block.removeWeek)
        #expect(screen.model.notice == "A block needs at least 2 weeks.")
        #expect(screen.model.block.title == "BLOCK · 2 WEEKS")
        let isUnchanged = screen.input.program == program
        #expect(isUnchanged, "the notice changed the program")
    }

    @Test("Minus on a last week with a finished workout changes nothing and names the week")
    func removeWeek_loggedLastWeek_namesTheWeek() throws {
        var input = try ProgramFixtures.seedInput()
        input.loggedWeeks = [0, 7]
        var screen = BuilderScreen(input)
        #expect(screen.model.block.removeWeek == .notice(.weekHasLoggedSessions(weekNumber: 8)))
        try screen.tap(screen.model.block.removeWeek)
        #expect(screen.model.notice == "Week 8 has logged sessions and can't be removed.")
        #expect(screen.model.block.title == "BLOCK · 8 WEEKS")
    }

    @Test("Minus carries the logged weeks to the edit when the last week is not among them")
    func removeWeek_loggedEarlierWeeks_isTheEditWithThem() throws {
        var input = try ProgramFixtures.seedInput()
        input.loggedWeeks = [0, 3]
        #expect(ProgramPresentation.make(input).block.removeWeek == .edit(.removeLastWeek(loggedWeeks: [0, 3])))
    }

    @Test("Each notice has its line, and each error of the Domain has its notice")
    func notices_haveTheirLines() {
        let locale = Fixtures.locale
        #expect(ProgramPresentation.text(of: .minimumTwoWeeks, locale: locale) == "A block needs at least 2 weeks.")
        #expect(
            ProgramPresentation.text(of: .weekHasLoggedSessions(weekNumber: 12), locale: locale)
                == "Week 12 has logged sessions and can't be removed."
        )
        #expect(
            ProgramPresentation.text(of: .dayHasNoExercises, locale: locale)
                == "Add at least one exercise before scheduling this day."
        )
        #expect(ProgramBuilderNotice(ProgramEditError.minimumTwoWeeks) == .minimumTwoWeeks)
        #expect(
            ProgramBuilderNotice(ProgramEditError.weekHasLoggedSessions(weekNumber: 8))
                == .weekHasLoggedSessions(weekNumber: 8)
        )
    }

    @Test("Cycling a weekday onto a day with no exercise assigns it and shows the notice until the next edit")
    func cycleOntoAnEmptyDay_showsTheNotice() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput())
        try screen.tap(screen.model.days.addDay.action)
        // Tuesday: rest, then the four days with exercises, then the new day, which has none.
        for _ in 0 ..< 4 {
            try screen.tapCell(.tuesday)
            #expect(screen.model.notice == nil)
        }
        #expect(try #require(screen.model.week.cell(.tuesday)).action
            == .edit(
                .setSchedule(week: 0, weekday: .tuesday, day: screen.input.program.days[4].id),
                notice: .dayHasNoExercises
            ))
        try screen.tapCell(.tuesday)
        var model = screen.model
        #expect(model.notice == "Add at least one exercise before scheduling this day.")
        #expect(try #require(model.week.cell(.tuesday)).label == "D5")
        #expect(try #require(model.week.cell(.tuesday)).spokenValue == "New day")
        #expect(model.block.chips[0].subtitle == "5 DAYS")
        // The next edit takes the notice away.
        try screen.tapCell(.thursday)
        model = screen.model
        #expect(model.notice == nil)
        #expect(try #require(model.week.cell(.tuesday)).label == "D5")
    }

    @Test("Selecting another week takes the notice away")
    func notice_goesWhenAnotherWeekIsSelected() throws {
        var input = try ProgramFixtures.seedInput()
        input.notice = .dayHasNoExercises
        var screen = BuilderScreen(input)
        #expect(screen.model.notice != nil)
        try screen.tap(screen.model.block.chips[1].action)
        #expect(screen.model.notice == nil)
    }

    @Test("In a program whose only day is empty, the first tap on a rest day carries the notice")
    func cycle_ontoTheOnlyDay_whenEmpty_carriesTheNotice() throws {
        let program = try ProgramFixtures.program(weekCount: 2, days: [ProgramFixtures.day(1)])
        var screen = try BuilderScreen(ProgramFixtures.input(program))
        try screen.tapCell(.monday)
        #expect(screen.model.notice == "Add at least one exercise before scheduling this day.")
        // The next tap goes back to rest, which needs no word.
        #expect(try #require(screen.model.week.cell(.monday)).action == .edit(.setSchedule(
            week: 0,
            weekday: .monday,
            day: nil
        )))
    }
}
