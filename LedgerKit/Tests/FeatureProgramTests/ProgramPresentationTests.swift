@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S5: the builder's display model for the brief's worked examples. This file holds criterion 1 (the seed
/// program, word for word), the header and the block; the selected week, the training days, the notices and
/// the odd programs are in the extension files.
@Suite("ProgramPresentation", .tags(.feature))
nonisolated struct ProgramPresentationTests {
    @Test("The seed program reads as the brief's criterion 1 gives it, word for word")
    func seedProgram_readsAsCriterionOne() throws {
        let model = try ProgramPresentation.make(ProgramFixtures.seedInput())
        #expect(model.header.eyebrow == "MY PROGRAM")
        #expect(model.header.name == "Upper / Lower")
        #expect(model.block.title == "BLOCK · 8 WEEKS")
        #expect(
            model.block.chipLine
                == "W1 4 DAYS · W2 4 DAYS · W3 4 DAYS · W4 4 DAYS · W5 4 DAYS · W6 4 DAYS · W7 4 DAYS · W8 DELOAD"
        )
        #expect(model.week.title == "WEEK 1")
        #expect(model.week.strip == "M UA · T REST · W LA · T REST · F UB · S LB · S REST")
        #expect(model.days.summary == "4 days · 58 sets a week")
        #expect(model.days.cards.map(\.name) == [
            "Upper A — Push focus", "Lower A — Squat focus", "Upper B — Pull focus", "Lower B — Hinge focus"
        ])
        #expect(model.days.cards.map(\.tag) == ["UA", "LA", "UB", "LB"])
        #expect(model.days.cards.map(\.meta) == [
            "5 exercises · 18 sets · ~39 min",
            "4 exercises · 15 sets · ~38 min",
            "4 exercises · 15 sets · ~37 min",
            "3 exercises · 10 sets · ~31 min"
        ])
        #expect(model.notice == nil)
    }

    @Test("The cards' minutes are TimeEstimate's for the slots as written: 39, 38, 37 and 31")
    func seedProgram_minutesAreTimeEstimates() throws {
        let program = try Fixtures.seedProgram()
        let estimates = program.days.map { TimeEstimate.minutes(day: $0, prescriptions: [:]) }
        #expect(estimates == [39, 38, 37, 31])
        let model = try ProgramPresentation.make(ProgramFixtures.input(program))
        for (card, minutes) in zip(model.days.cards, estimates) {
            #expect(card.meta.hasSuffix(" · ~\(minutes) min"), "\(card.meta)")
        }
    }

    @Test("The header holds the eyebrow, the program's name as stored and the field's placeholder")
    func header_holdsTheNameAndItsPlaceholder() throws {
        var input = try ProgramFixtures.seedInput()
        input.program.name = "Winter block"
        let header = ProgramPresentation.make(input).header
        #expect(header.eyebrow == "MY PROGRAM")
        #expect(header.name == "Winter block")
        #expect(header.namePlaceholder == "Program name")
    }

    @Test("A typed name is one edit, and the header then shows the cleaned name")
    func header_rename_isOneEdit() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput())
        try screen.tap(.edit(.renameProgram("  Winter block\n")))
        #expect(screen.model.header.name == "Winter block")
        try screen.tap(.edit(.renameProgram("   ")))
        #expect(screen.model.header.name == "Winter block")
    }

    @Test("The block names its length, speaks it as one adjustable value, and marks the selected chip alone")
    func block_namesItsLengthAndMarksTheSelectedChip() throws {
        let block = try ProgramPresentation.make(ProgramFixtures.seedInput(selectedWeek: 2)).block
        #expect(block.title == "BLOCK · 8 WEEKS")
        #expect(block.spokenLabel == "Block length")
        #expect(block.spokenValue == "8 weeks")
        #expect(block.chips.count == 8)
        #expect(block.selectedPlaces == [2])
        #expect(block.chips.map(\.action) == (0 ..< 8).map { .selectWeek($0) })
    }

    @Test("A chip reads W and its number with the week's training days, or DELOAD; VoiceOver hears the same")
    func chips_readTheDaysOrDeload_andSpeakTheSame() throws {
        let chips = try ProgramPresentation.make(ProgramFixtures.seedInput()).block.chips
        let first = try #require(chips.first)
        #expect(first.title == "W1")
        #expect(first.subtitle == "4 DAYS")
        #expect(!first.isDeload)
        #expect(first.spokenLabel == "Week 1")
        #expect(first.spokenValue == "4 days")
        let last = try #require(chips.last)
        #expect(last.title == "W8")
        #expect(last.subtitle == "DELOAD")
        #expect(last.isDeload)
        #expect(last.spokenLabel == "Week 8")
        #expect(last.spokenValue == "Deload")
    }

    @Test("A week that trains one day reads 1 DAY, and one that trains none 0 DAYS")
    func chips_oneDayAndNoDay_takeThePluralForm() throws {
        var input = try ProgramFixtures.seedInput()
        let upperA = input.program.days[ProgramFixtures.DayIndex.upperA].id
        input.program.weeks[0].schedule = [.monday: upperA]
        input.program.weeks[1].schedule = [:]
        let chips = ProgramPresentation.make(input).block.chips
        #expect(chips[0].subtitle == "1 DAY")
        #expect(chips[0].spokenValue == "1 day")
        #expect(chips[1].subtitle == "0 DAYS")
        #expect(chips[1].spokenValue == "0 days")
    }

    @Test("Tapping a chip selects its week: the title, the strip and the mark follow")
    func chip_tap_selectsItsWeek() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput())
        try screen.tap(screen.model.block.chips[7].action)
        let model = screen.model
        #expect(model.block.selectedPlaces == [7])
        #expect(model.week.title == "WEEK 8 · DELOAD")
        #expect(model.week.strip == "M UA · T REST · W LA · T REST · F UB · S REST · S REST")
    }

    @Test("Plus appends a copy of the last week's schedule, not a deload, and selects it")
    func addWeek_appendsTheLastWeeksScheduleAndSelectsIt() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput())
        #expect(screen.model.block.addWeek == .addWeek(selecting: 8))
        try screen.tap(screen.model.block.addWeek)
        let model = screen.model
        #expect(model.block.title == "BLOCK · 9 WEEKS")
        #expect(model.block.spokenValue == "9 weeks")
        #expect(model.block.selectedPlaces == [8])
        #expect(model.block.chips.last?.subtitle == "3 DAYS")
        #expect(model.week.title == "WEEK 9")
        #expect(model.week.strip == "M UA · T REST · W LA · T REST · F UB · S REST · S REST")
        #expect(!model.week.deload.isOn)
    }

    @Test("Minus removes the last week when the block allows it, and the selection stays inside the block")
    func removeWeek_dropsTheLastWeek_andTheSelectionStaysInside() throws {
        var screen = try BuilderScreen(ProgramFixtures.seedInput(selectedWeek: 7))
        #expect(screen.model.block.removeWeek == .edit(.removeLastWeek(loggedWeeks: [])))
        try screen.tap(screen.model.block.removeWeek)
        let model = screen.model
        #expect(model.block.title == "BLOCK · 7 WEEKS")
        #expect(model.block.selectedPlaces == [6])
        #expect(model.week.title == "WEEK 7")
        #expect(model.notice == nil)
    }
}
