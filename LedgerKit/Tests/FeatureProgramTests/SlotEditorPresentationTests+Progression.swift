@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 criterion 4, the brief's criterion 9: the progression chips with their notes, and the drop set.
nonisolated extension SlotEditorPresentationTests {
    // MARK: Progression

    @Test("The three chips read Linear, Double and Fixed, the slot's own selected and offering nothing")
    func progression_chips_markTheSlotsOwn() throws {
        let details = try Self.seedScreen(open: "1").details()
        #expect(details.progression.title == "PROGRESSION")
        #expect(details.progression.chips.map(\.title) == ["Linear", "Double", "Fixed"])
        #expect(details.selectedProgressions == ["Linear"])
        #expect(details.progression.chips.map { $0.action == nil } == [true, false, false])
    }

    @Test("Each progression has the brief's note, with the slot's step and start load in pounds")
    func progression_notes_areTheBriefs() throws {
        #expect(try Self.seedScreen(open: "1").details().progression.note
            == "Adds 5 lb a week from 180 lb. A week with a missed set holds the load.")
        #expect(try Self.seedScreen(open: "2").details().progression.note
            == "Adds a rep each week up to 12, then +2.5 lb back at 10.")
        var lowerA = try DayScreen(DayEditorFixtures.seedInput(dayIndex: ProgramFixtures.DayIndex.lowerA))
        try lowerA.open("3B")
        #expect(try lowerA.details().progression.note == "Stays at 160 lb for the whole block.")
        #expect(try lowerA.details().selectedProgressions == ["Fixed"])
    }

    @Test("In kilograms the notes name kilograms and the unit's step")
    func progression_notes_kilograms() throws {
        let incline = Fixtures.CatalogID.inclineDBPress
        var screen = try Self.screen(DayEditorFixtures.slot(1, incline, startLoad: .kilograms(22.5)), units: .kg)
        #expect(try screen.details().progression.note
            == "Adds 1.25 kg a week from 22.5 kg. A week with a missed set holds the load.")
        try screen.tap(screen.details().progression.chips[1].action)
        #expect(try screen.details().progression.note == "Adds a rep each week up to 10, then +1.25 kg back at 8.")
        try screen.tap(screen.details().progression.chips[2].action)
        #expect(try screen.details().progression.note == "Stays at 22.5 kg for the whole block.")
    }

    @Test("Double chosen on reps 8 with the top at 9 makes the top 10 and relabels the fields (criterion 9)")
    func chooseDouble_widensTheRangeAndRelabels() throws {
        var screen = try Self.screen(DayEditorFixtures.slot(1, reps: 8, repsHi: 9))
        #expect(try screen.details().fieldLine.hasPrefix("SETS 3 · REPS 8 · START LOAD"))
        try screen.tap(screen.details().progression.chips[1].action)
        #expect(try screen.details().fieldLine.hasPrefix("SETS 3 · REP FLOOR 8 · TOP OF RANGE 10 · START LOAD"))
        #expect(try screen.details().progression.note == "Adds a rep each week up to 10, then +5 lb back at 8.")
        #expect(try screen.details().selectedProgressions == ["Double"])
        #expect(try screen.content().row("1").sub == "Barbell · Reps 8–10 · RPE 8 · 1:30 rest")
        // The panel stays open, and the chosen chip now offers nothing.
        #expect(try screen.details().progression.chips.map { $0.action == nil } == [false, true, false])
    }

    @Test("Leaving Double keeps the top of the range, hidden, and it is there on the way back (behaviour 12)")
    func leaveDouble_keepsTheTop() throws {
        var screen = try Self.seedScreen(open: "2")
        try screen.step("TOP OF RANGE", .upward, times: 3)
        try screen.tap(screen.details().progression.chips[0].action)
        #expect(try screen.details().fields.map(\.label).contains("TOP OF RANGE") == false)
        try screen.tap(screen.details().progression.chips[1].action)
        #expect(try screen.details().value("TOP OF RANGE") == "15")
    }

    // MARK: Drop set

    @Test("The drop set switch turns on and off, with the brief's two notes, and the row says drop")
    func dropSet_turnsOnAndOff() throws {
        var screen = try Self.seedScreen(open: "1")
        var dropSet = try screen.details().dropSet
        #expect(dropSet.title == "Drop set")
        #expect(dropSet.isOn == false)
        #expect(dropSet.note == "One extra set at −15% after the last working set.")
        try screen.tap(dropSet.action)
        dropSet = try screen.details().dropSet
        #expect(dropSet.isOn)
        #expect(dropSet.note == "One extra set at −15%, straight after the last working set.")
        #expect(try screen.content().row("1").sub == "Barbell · +5/wk · drop · RPE 8 · 2:30 rest")
        #expect(try screen.content().header.meta.hasPrefix("Week 1 · 5 exercises · 19 sets · "))
        try screen.tap(dropSet.action)
        #expect(try screen.details().dropSet.isOn == false)
        #expect(try screen.content().header.meta.hasPrefix("Week 1 · 5 exercises · 18 sets · "))
    }
}
