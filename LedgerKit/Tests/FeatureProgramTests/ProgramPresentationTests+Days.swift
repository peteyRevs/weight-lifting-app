@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The training days: the summary, the cards (the brief's criteria 5 and 6 as the builder shows them) and
/// "+ Add training day".
nonisolated extension ProgramPresentationTests {
    @Test("The section holds its title, the summary, the helper line and the add button")
    func trainingDays_holdTheirFixedTexts() throws {
        let days = try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: 3)).days
        #expect(days.title == "TRAINING DAYS")
        #expect(days.helper == "Shared by every week. The schedule above decides which day you train, and when.")
        #expect(days.addDay.title == "+ Add training day")
        #expect(days.addDay.action == .addDay(name: "New day", weekIndex: 3))
    }

    @Test("A card names the first four exercises by their short names, then counts the rest")
    func dayCard_chips_nameFourThenCountTheRest() throws {
        let cards = try ProgramPresentation.make(ProgramFixtures.seedInput()).days.cards
        #expect(cards[ProgramFixtures.DayIndex.upperA].chips == ["BENCH", "INCLINE", "CS ROW", "PULLDOWN", "+1"])
        #expect(cards[ProgramFixtures.DayIndex.lowerA].chips == ["SQUAT", "RDL", "LEG PRESS", "CALF"])
        #expect(cards[ProgramFixtures.DayIndex.lowerB].chips == ["DEADLIFT", "FRONT SQ", "LEG CURL"])
    }

    @Test("A card opens the Day editor on its day, in the selected week, and speaks its name and its meta line")
    func dayCard_carriesTheRouteAndSpeaksWhatIsDrawn() throws {
        let input = try ProgramFixtures.seedInput(selectedWeek: 4)
        let cards = ProgramPresentation.make(input).days.cards
        #expect(cards.map(\.id) == input.program.days.map(\.id))
        #expect(cards.map(\.action) == input.program.days.map { .route(.day($0.id, weekIndex: 4)) })
        for card in cards {
            #expect(card.spokenLabel == card.name)
            #expect(card.spokenValue == card.meta)
        }
        var screen = BuilderScreen(input)
        try screen.tap(cards[ProgramFixtures.DayIndex.lowerA].action)
        #expect(screen.routes == [.day(input.program.days[ProgramFixtures.DayIndex.lowerA].id, weekIndex: 4)])
    }

    @Test("A card counts the slots' own numbers, whichever week is selected: a deload week changes nothing")
    func dayCard_meta_isTheSlotsOwn() throws {
        let normal = try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: 0)).days
        let deload = try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: 7)).days
        #expect(deload.cards.map(\.meta) == normal.cards.map(\.meta))
        #expect(deload.summary == normal.summary)
        // Upper B's curl has a drop set: 4 + 4 + 3 + 3 working sets and the one drop set.
        #expect(normal.cards[ProgramFixtures.DayIndex.upperB].meta == "4 exercises · 15 sets · ~37 min")
    }

    @Test("A day with one exercise of one set takes the singular forms")
    func dayCard_meta_oneExerciseOneSet_isSingular() throws {
        var day = try ProgramFixtures.day(1, slotCount: 1)
        day.slots[0].sets = 1
        let input = try ProgramFixtures.input(ProgramFixtures.program(weekCount: 2, days: [day]))
        let days = ProgramPresentation.make(input).days
        let minutes = TimeEstimate.minutes(day: day, prescriptions: [:])
        #expect(days.cards.map(\.meta) == ["1 exercise · 1 set · ~\(minutes) min"])
        #expect(days.summary == "1 day · 1 set a week")
        #expect(days.cards.map(\.chips) == [["BENCH"]])
    }

    @Test("Add training day makes New day, tagged D5, with no slots, and opens the Day editor on it")
    func addDay_makesNewDayAndOpensIt() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput(selectedWeek: 1))
        try screen.tap(screen.model.days.addDay.action)
        let days = screen.model.days
        let card = try #require(days.cards.last)
        #expect(days.cards.count == 5)
        #expect(card.name == "New day")
        #expect(card.tag == "D5")
        #expect(card.meta == "No exercises yet")
        #expect(card.chips == [])
        #expect(card.spokenValue == "No exercises yet")
        #expect(days.summary == "5 days · 58 sets a week")
        #expect(screen.routes == [.day(card.id, weekIndex: 1)])
        // No schedule changed.
        #expect(screen.model.block.chips.map(\.subtitle).prefix(2) == ["4 DAYS", "4 DAYS"])
    }

    @Test("After a day scheduled in eight weeks is deleted, its card is gone and its weekdays read REST")
    func deletedDay_isGoneFromTheCardsAndTheSchedule() throws {
        var input = try ProgramFixtures.seedInput()
        let upperA = input.program.days[ProgramFixtures.DayIndex.upperA]
        #expect(input.program.weeks.count { $0.schedule.values.contains(upperA.id) } == 8)
        // The delete and its confirmation are the Day editor's (S6); the builder shows what is left.
        input.program = ProgramEditing.deleteDay(input.program, day: upperA.id)
        let model = ProgramPresentation.make(input)
        #expect(model.days.cards.map(\.tag) == ["LA", "UB", "LB"])
        #expect(model.days.summary == "3 days · 40 sets a week")
        #expect(model.week.strip == "M REST · T REST · W LA · T REST · F UB · S LB · S REST")
        #expect(model.block
            .chipLine ==
            "W1 3 DAYS · W2 3 DAYS · W3 3 DAYS · W4 3 DAYS · W5 3 DAYS · W6 3 DAYS · W7 3 DAYS · W8 DELOAD")
        input.selectedWeek = 7
        #expect(ProgramPresentation.make(input).week
            .strip == "M REST · T REST · W LA · T REST · F UB · S REST · S REST")
    }

    @Test("A slot whose exercise is not stored is counted and named by a dash")
    func dayCard_missingExercise_isCountedAndNamedByADash() throws {
        var input = try ProgramFixtures.seedInput()
        input.exercises[Fixtures.CatalogID.backSquat] = nil
        let card = ProgramPresentation.make(input).days.cards[ProgramFixtures.DayIndex.lowerA]
        #expect(card.chips == ["—", "RDL", "LEG PRESS", "CALF"])
        #expect(card.meta == "4 exercises · 15 sets · ~38 min")
        // An input that was handed no exercise at all.
        let unfilled = ProgramBuilderInput(
            program: input.program,
            settings: input.settings,
            selectedWeek: 0,
            calendar: input.calendar,
            locale: input.locale
        )
        let bare = ProgramPresentation.make(unfilled).days
        #expect(bare.cards[ProgramFixtures.DayIndex.upperA].chips == ["—", "—", "—", "—", "+1"])
        #expect(bare.summary == "4 days · 58 sets a week")
    }
}
