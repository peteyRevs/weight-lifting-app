@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Criterion 9: the presentation is total and reads nothing but its input. The odd programs: no days, every
/// week a deload, sixteen weeks by six days, a selection outside the block, a schedule that names a day the
/// program does not hold.
nonisolated extension ProgramPresentationTests {
    @Test("A program with no days shows a week of rest, no card and the add button; a tap on a cell changes nothing")
    func noDays_showsRestAndNoCard() throws {
        let program = try ProgramFixtures.program(weekCount: 2, days: [])
        var screen = try BuilderScreen(ProgramFixtures.input(program))
        let model = screen.model
        #expect(model.block.chipLine == "W1 0 DAYS · W2 0 DAYS")
        #expect(model.week.strip == "M REST · T REST · W REST · T REST · F REST · S REST · S REST")
        #expect(model.days.summary == "0 days · 0 sets a week")
        #expect(model.days.cards.isEmpty)
        #expect(model.days.addDay.action == .addDay(name: "New day", weekIndex: 0))
        try screen.tapCell(.monday)
        #expect(screen.input.program == program)
        #expect(screen.model.notice == nil)
    }

    @Test("A block whose every week is a deload reads DELOAD on every chip and in the title")
    func everyWeekADeload_readsDeloadEverywhere() throws {
        var input = try ProgramFixtures.seedInput(selectedWeek: 3)
        for place in input.program.weeks.indices {
            input.program.weeks[place].isDeload = true
        }
        let model = ProgramPresentation.make(input)
        #expect(Set(model.block.chips.map(\.subtitle)) == ["DELOAD"])
        #expect(Set(model.block.chips.map(\.spokenValue)) == ["Deload"])
        #expect(model.week.title == "WEEK 4 · DELOAD")
        #expect(model.week.deload.isOn)
        #expect(model.days.summary == "4 days · 58 sets a week")
    }

    @Test("Sixteen weeks by six days: sixteen chips, six cards, and every day of the week assigned")
    func sixteenWeeksBySixDays_isWhole() throws {
        let days = try (1 ... 6).map { try ProgramFixtures.day($0, slotCount: $0) }
        var program = try ProgramFixtures.program(weekCount: 16, days: days)
        let schedule = Dictionary(uniqueKeysWithValues: zip(Weekday.allCases, days.map(\.id)))
        for place in program.weeks.indices {
            program.weeks[place].schedule = schedule
        }
        let model = try ProgramPresentation.make(ProgramFixtures.input(program, selectedWeek: 15))
        #expect(model.block.title == "BLOCK · 16 WEEKS")
        #expect(model.block.chips.count == 16)
        #expect(Set(model.block.chips.map(\.subtitle)) == ["6 DAYS"])
        #expect(model.block.chips.last?.title == "W16")
        #expect(model.week.title == "WEEK 16")
        #expect(model.week.strip == "M D1 · T D2 · W D3 · T D4 · F D5 · S D6 · S REST")
        #expect(model.days.cards.count == 6)
        // 1 + 2 + … + 6 slots of three sets each.
        #expect(model.days.summary == "6 days · 63 sets a week")
        #expect(model.days.cards.last?.chips == ["BENCH", "BENCH", "BENCH", "BENCH", "+2"])
    }

    @Test(
        "A selected week outside the block reads as the nearest week, and every action names that week",
        arguments: [(-1, 0), (Int.min, 0), (0, 0), (7, 7), (8, 7), (99, 7), (Int.max, 7)]
    )
    func selectedWeek_outsideTheBlock_readsAsTheNearest(selected: Int, nearest: Int) throws {
        let model = try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: selected))
        #expect(model.block.selectedPlaces == [nearest])
        #expect(model.week.title == (nearest == 7 ? "WEEK 8 · DELOAD" : "WEEK 1"))
        #expect(model.week.deload.action == .edit(.toggleDeload(week: nearest)))
        #expect(model.week.cells.first?.action == .edit(.cycleSchedule(week: nearest, weekday: .monday)))
        #expect(model.days.addDay.action == .addDay(name: "New day", weekIndex: nearest))
        #expect(model.days.cards.first?.action == .route(.day(DayTemplateID(Fixtures.uuid(300)), weekIndex: nearest)))
    }

    @Test("A schedule entry that names a day the program does not hold reads as rest, on the chip and in the cell")
    func scheduleNamingAMissingDay_readsAsRest() throws {
        var input = try ProgramFixtures.seedInput()
        input.program.weeks[0].schedule[.sunday] = DayTemplateID(Fixtures.uuid(999))
        var screen = BuilderScreen(input)
        #expect(screen.model.week.strip == "M UA · T REST · W LA · T REST · F UB · S LB · S REST")
        #expect(screen.model.block.chips[0].subtitle == "4 DAYS")
        // The Domain's cycle reads it as rest too: the tap assigns the first day.
        try screen.tapCell(.sunday)
        #expect(try #require(screen.model.week.cell(.sunday)).label == "UA")
    }

    @Test("A program emptied of its weeks and its days does not trap: a week of rest and nothing to select")
    func noWeeks_doesNotTrap() throws {
        var input = try ProgramFixtures.seedInput(selectedWeek: 3)
        input.program.weeks = []
        input.program.days = []
        let model = ProgramPresentation.make(input)
        #expect(model.block.chips.isEmpty)
        #expect(model.block.removeWeek == .notice(.minimumTwoWeeks))
        #expect(model.week.title == "WEEK 1")
        #expect(model.week.cells.map(\.isRest) == Array(repeating: true, count: 7))
        #expect(model.week.applyToLater == nil)
        #expect(model.days.cards.isEmpty)
    }

    @Test("The same exercises give the same model in whatever order they were put in the input")
    func exercises_inAnyOrder_giveTheSameModel() throws {
        let input = try ProgramFixtures.seedInput()
        let expected = ProgramPresentation.make(input)
        var generator = SeededGenerator(seed: 11)
        for _ in 0 ..< 5 {
            var shuffled = input
            shuffled.exercises = [:]
            for exercise in input.exercises.values.shuffled(using: &generator) {
                shuffled.exercises[exercise.id] = exercise
            }
            let isSame = ProgramPresentation.make(shuffled) == expected
            #expect(isSame)
        }
    }

    @Test("The model does not depend on the calendar's own locale, first weekday or time zone")
    func calendarsOwnSettings_doNotReachTheModel() throws {
        let input = try ProgramFixtures.seedInput()
        let expected = ProgramPresentation.make(input)
        var other = input
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = 4
        calendar.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        other.calendar = calendar
        let isSame = ProgramPresentation.make(other) == expected
        #expect(isSame)
    }

    @Test("A day with an empty name or tag is drawn as it is stored: data is not the presentation's to mend")
    func dayWithoutNameOrTag_isDrawnAsStored() throws {
        var input = try ProgramFixtures.seedInput()
        input.program.days[0].name = ""
        input.program.days[0].tag = ""
        let model = ProgramPresentation.make(input)
        #expect(model.days.cards[0].name == "")
        #expect(try #require(model.week.cell(.monday)).label == "")
        #expect(try #require(model.week.cell(.monday)).isRest == false)
    }
}
