@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The selected week: its title, the seven cells in the order of the week start with the calendar's letters,
/// the cycle of a cell (the brief's criterion 2) and the week's three actions (criterion 3).
nonisolated extension ProgramPresentationTests {
    @Test("Tuesday cycles through the four days in order and back to rest, and the chip's count follows")
    func cell_taps_cycleThroughTheDaysAndBackToRest() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput())
        var labels: [String] = []
        var counts: [String] = []
        for _ in 0 ..< 6 {
            try screen.tapCell(.tuesday)
            let model = screen.model
            try labels.append(#require(model.week.cell(.tuesday)).label)
            counts.append(model.block.chips[0].subtitle)
        }
        // The plan's reading of criterion 2 (rule 5): four taps reach the fourth day, the fifth is rest.
        #expect(labels == ["UA", "LA", "UB", "LB", "REST", "UA"])
        #expect(counts == ["5 DAYS", "5 DAYS", "5 DAYS", "5 DAYS", "4 DAYS", "5 DAYS"])
        // Only week 1 changed.
        #expect(screen.model.block.chips[1].subtitle == "4 DAYS")
    }

    @Test("A cell's action is the cycle of its own weekday in the selected week")
    func cells_eachCarriesTheCycleOfItsWeekday() throws {
        let cells = try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: 2)).week.cells
        #expect(cells.map(\.weekday) == Weekday.allCases)
        #expect(cells.map(\.action) == Weekday.allCases.map { .edit(.cycleSchedule(week: 2, weekday: $0)) })
    }

    @Test("A cell says whether it is rest, and VoiceOver hears the weekday, then rest or the day's short title")
    func cells_speakTheWeekdayAndWhatIsDrawn() throws {
        let week = try ProgramPresentation.make(ProgramFixtures.seedInput()).week
        #expect(week.hint == "Tap to assign")
        #expect(week.cells.map(\.isRest) == [false, true, false, true, false, false, true])
        #expect(
            week.spokenStrip == "Monday, Upper A · Tuesday, Rest · Wednesday, Lower A · Thursday, Rest · "
                + "Friday, Upper B · Saturday, Lower B · Sunday, Rest"
        )
        #expect(Set(week.cells.map(\.spokenHint)) == ["Double-tap to assign"])
    }

    @Test("With a Sunday week start the strip begins on Sunday; each cell still names its own weekday")
    func cells_sundayStart_beginOnSunday() throws {
        var input = try ProgramFixtures.seedInput()
        input.settings.weekStart = .sunday
        let week = ProgramPresentation.make(input).week
        #expect(week.strip == "S REST · M UA · T REST · W LA · T REST · F UB · S LB")
        #expect(week.cells.map(\.weekday) == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        #expect(week.cells.first?.spokenLabel == "Sunday")
        #expect(week.cells.first?.action == .edit(.cycleSchedule(week: 0, weekday: .sunday)))
    }

    @Test(
        "The strip begins on the settings' week start, whichever weekday it is, and holds each weekday once",
        arguments: Weekday.allCases
    )
    func cells_anyWeekStart_beginOnIt(weekStart: Weekday) throws {
        var input = try ProgramFixtures.seedInput()
        input.settings.weekStart = weekStart
        let weekdays = ProgramPresentation.make(input).week.cells.map(\.weekday)
        #expect(weekdays.first == weekStart)
        #expect(weekdays.count == 7)
        #expect(Set(weekdays).count == 7)
        // Each cell is the day after the one before it.
        for (cell, next) in zip(weekdays, weekdays.dropFirst()) {
            #expect(next.rawValue == cell.rawValue % 7 + 1)
        }
    }

    @Test("The letters and the spoken names follow the injected locale, not the catalog and not the calendar's own")
    func scheduleStrip_lettersFollowTheLocale() throws {
        var input = try ProgramFixtures.seedInput()
        input.locale = Locale(identifier: "de_DE")
        let german = ProgramPresentation.make(input).week
        #expect(german.cells.map(\.letter) == ["M", "D", "M", "D", "F", "S", "S"])
        #expect(german.cells.map(\.spokenLabel).prefix(2) == ["Montag", "Dienstag"])
        input.locale = Locale(identifier: "fr_FR")
        input.settings.weekStart = .sunday
        let french = ProgramPresentation.make(input).week
        #expect(french.cells.map(\.letter) == ["D", "L", "M", "M", "J", "V", "S"])
        #expect(french.cells.map(\.spokenLabel).prefix(2) == ["dimanche", "lundi"])
        // The calendar's own locale is English; the tags and the catalog's words are not the system's to change.
        #expect(input.calendar.locale == Fixtures.locale)
        #expect(french.cells.map(\.label) == ["REST", "UA", "REST", "LA", "REST", "UB", "LB"])
    }

    @Test("A weekday's symbol is the one at its place from Sunday; a calendar with none there gives no text")
    func symbol_isTheOneAtTheWeekdaysPlaceFromSunday() {
        let symbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        #expect(Weekday.allCases.map { ProgramPresentation.symbol(of: $0, in: symbols) }
            == ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])
        #expect(ProgramPresentation.symbol(of: .sunday, in: []) == "")
        #expect(ProgramPresentation.symbol(of: .saturday, in: ["Su", "Mo"]) == "")
        #expect(ProgramPresentation.symbol(of: .monday, in: ["Su", "Mo"]) == "Mo")
    }

    @Test("Copy week 2 gives week 3 the schedule of week 2")
    func weekActions_copyPrevious_takesTheWeekBefore() throws {
        var input = try ProgramFixtures.seedInput(selectedWeek: 2)
        let lowerB = input.program.days[ProgramFixtures.DayIndex.lowerB].id
        input.program.weeks[1].schedule = [.tuesday: lowerB]
        var screen = BuilderScreen(input)
        let copy = screen.model.week.copyPrevious
        #expect(copy.title == "Copy week 2")
        #expect(copy.action == .edit(.copyPreviousWeek(week: 2)))
        #expect(screen.model.week.strip == "M UA · T REST · W LA · T REST · F UB · S LB · S REST")
        try screen.tap(copy.action)
        #expect(screen.model.week.strip == "M REST · T LB · W REST · T REST · F REST · S REST · S REST")
        #expect(screen.model.block.chips[2].subtitle == "1 DAY")
    }

    @Test("On the first week the copy button reads First week and is disabled")
    func weekActions_firstWeek_isDisabled() throws {
        let week = try ProgramPresentation.make(ProgramFixtures.seedInput()).week
        #expect(week.copyPrevious == ProgramBuilderModel.Control(title: "First week", action: nil))
    }

    @Test("Apply to later weeks copies week 3 to weeks 4 to 8 and leaves every deload flag")
    func weekActions_applyToLater_copiesTheScheduleNotTheDeload() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput(selectedWeek: 2))
        try screen.tapCell(.tuesday)
        let apply = try #require(screen.model.week.applyToLater)
        #expect(apply.title == "Apply to later weeks")
        #expect(apply.action == .edit(.applyToLaterWeeks(week: 2)))
        try screen.tap(apply.action)
        let block = screen.model.block
        #expect(block
            .chipLine ==
            "W1 4 DAYS · W2 4 DAYS · W3 5 DAYS · W4 5 DAYS · W5 5 DAYS · W6 5 DAYS · W7 5 DAYS · W8 DELOAD")
        #expect(block.chips.map(\.isDeload) == [false, false, false, false, false, false, false, true])
        // Week 8 is still the deload and now trains what week 3 trains.
        try screen.tap(block.chips[7].action)
        #expect(screen.model.week.title == "WEEK 8 · DELOAD")
        #expect(screen.model.week.strip == "M UA · T UA · W LA · T REST · F UB · S LB · S REST")
        #expect(screen.model.block.chips[7].spokenValue == "Deload")
    }

    @Test("The last week has no later week: Apply to later weeks is absent")
    func weekActions_lastWeek_hasNoApplyToLater() throws {
        #expect(try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: 7)).week.applyToLater == nil)
        #expect(try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: 6)).week.applyToLater != nil)
    }

    @Test("Deload toggles week 3: its title and its chip read DELOAD, and a second tap takes it back")
    func weekActions_deload_togglesTheWeek() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput(selectedWeek: 2))
        let before = screen.model.week.deload
        #expect(before == ProgramBuilderModel.Toggle(
            title: "Deload",
            isOn: false,
            action: .edit(.toggleDeload(week: 2))
        ))
        try screen.tap(before.action)
        var model = screen.model
        #expect(model.week.title == "WEEK 3 · DELOAD")
        #expect(model.week.deload.isOn)
        #expect(model.block.chips[2].subtitle == "DELOAD")
        #expect(model.block.chips[2].isDeload)
        // The schedule is untouched: a deload week keeps its days.
        #expect(model.week.strip == "M UA · T REST · W LA · T REST · F UB · S LB · S REST")
        try screen.tap(model.week.deload.action)
        model = screen.model
        #expect(model.week.title == "WEEK 3")
        #expect(model.block.chips[2].subtitle == "4 DAYS")
    }
}
