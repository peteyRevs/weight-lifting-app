@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 criterion 5, the brief's criterion 7: the shown week's line and the strip of every week's load, from
/// `ProgressionRules.prescriptions`, in pounds and in kilograms, with the deload and the held marks.
nonisolated extension SlotEditorPresentationTests {
    /// Lower A of the seed program with Back Squat open, its misses set.
    static func squatScreen(weekIndex: Int, misses: Set<Int> = []) throws -> DayScreen {
        var input = try DayEditorFixtures.seedInput(dayIndex: ProgramFixtures.DayIndex.lowerA, weekIndex: weekIndex)
        input.program.days[ProgramFixtures.DayIndex.lowerA].slots[0].misses = misses
        var screen = DayScreen(input)
        try screen.open("1")
        return screen
    }

    @Test("Incline DB Press reads 50, 50, 50, 52.5, 52.5, 52.5, 55 and 47.5 in the deload (criterion 7)")
    func weekStrip_inclineDBPress_followsRuleTen() throws {
        let strip = try Self.seedScreen(open: "2").details().strip
        #expect(strip.text == "W1 50 · W2 50 · W3 50 · W4 52.5 · W5 52.5 · W6 52.5 · W7 55 · W8 47.5 (deload)")
        #expect(strip.entries.map(\.text) == [
            "W1 50", "W2 50", "W3 50", "W4 52.5", "W5 52.5", "W6 52.5", "W7 55", "W8 47.5 (deload)"
        ])
        #expect(strip.entries.map(\.isDeload) == [false, false, false, false, false, false, false, true])
        #expect(strip.entries.map(\.isShown) == [true, false, false, false, false, false, false, false])
        #expect(strip.entries.allSatisfy { !$0.isHeld })
    }

    @Test("The week line follows the reps of rule 10 week by week", arguments: [
        (0, "WEEK 1", "3 × 10 @ 50 lb · RPE 8"), (1, "WEEK 2", "3 × 11 @ 50 lb · RPE 8"),
        (2, "WEEK 3", "3 × 12 @ 50 lb · RPE 8"), (3, "WEEK 4", "3 × 10 @ 52.5 lb · RPE 8"),
        (6, "WEEK 7", "3 × 10 @ 55 lb · RPE 8"), (7, "WEEK 8 · DELOAD", "2 × 11 @ 47.5 lb · RPE 6")
    ])
    func weekLine_inclineDBPress_followsRuleTen(weekIndex: Int, eyebrow: String, line: String) throws {
        let week = try Self.seedScreen(open: "2", weekIndex: weekIndex).details().week
        #expect(week.eyebrow == eyebrow)
        #expect(week.line == line)
        #expect(week.isDeload == (weekIndex == 7))
        #expect(week.isHeld == false)
    }

    @Test("Back Squat reads W8 240 (deload) under the eyebrow WEEK 8 · DELOAD (criterion 7)")
    func weekStrip_marksTheDeloadWeek() throws {
        let details = try Self.squatScreen(weekIndex: 7).details()
        #expect(details.strip.text
            == "W1 250 · W2 255 · W3 260 · W4 265 · W5 270 · W6 275 · W7 280 · W8 240 (deload)")
        #expect(details.strip.entries.last?.text == "W8 240 (deload)")
        #expect(details.strip.entries.map(\.isShown).last == true)
        #expect(details.week.eyebrow == "WEEK 8 · DELOAD")
        #expect(details.week.line == "4 × 5 @ 240 lb · RPE 6")
        #expect(details.week.isDeload)
    }

    @Test("The week after a missed week is marked HELD and holds the load (criterion 7)")
    func weekLine_deloadAndHeld() throws {
        // Week 3 was missed: week 4 holds 260.
        let details = try Self.squatScreen(weekIndex: 3, misses: [2]).details()
        #expect(details.week.eyebrow == "WEEK 4 · HELD")
        #expect(details.week.line == "5 × 5 @ 260 lb · RPE 8")
        #expect(details.week.isHeld)
        #expect(details.week.isDeload == false)
        #expect(details.strip.text
            == "W1 250 · W2 255 · W3 260 · W4 260 (held) · W5 265 · W6 270 · W7 275 · W8 240 (deload)")
        #expect(details.strip.entries.map(\.isHeld) == [false, false, false, true, false, false, false, false])
        // The week before the miss is not held.
        #expect(try Self.squatScreen(weekIndex: 2, misses: [2]).details().week.eyebrow == "WEEK 3")
    }

    @Test("A deload week after a missed week reads as a deload: a week carries one mark")
    func weekLine_deloadAfterAMiss_readsDeload() throws {
        let details = try Self.squatScreen(weekIndex: 7, misses: [6]).details()
        #expect(details.week.eyebrow == "WEEK 8 · DELOAD")
        #expect(details.week.isDeload)
        #expect(details.week.isHeld == false)
        #expect(details.strip.entries.last?.text == "W8 240 (deload)")
        #expect(details.strip.entries.last?.isHeld == false)
    }

    @Test("In kilograms the strip and the line print kilograms, by the unit's steps")
    func weekStrip_kilograms() throws {
        let incline = Fixtures.CatalogID.inclineDBPress
        let slot = try DayEditorFixtures.slot(
            1,
            incline,
            reps: 10,
            repsHi: 12,
            progression: .double,
            startLoad: .kilograms(20)
        )
        var screen = try Self.screen(slot, units: .kg)
        screen.input.weekIndex = 3
        let details = try screen.details()
        #expect(details.strip.text
            == "W1 20 · W2 20 · W3 20 · W4 21.25 · W5 21.25 · W6 21.25 · W7 22.5 · W8 18.75 (deload)")
        #expect(details.week.line == "3 × 10 @ 21.25 kg · RPE 8")
        #expect(try screen.content().row("1").load == "21.25 kg")
        // The seed's pounds, read in kilograms: converted to one decimal, stepped by the kilogram step.
        var seed = try DayEditorFixtures.seedInput()
        seed.settings.units = .kg
        seed.openSlot = seed.program.days[0].slots[1].id
        let converted = try DayEditorPresentation.make(seed).content().row("2")
        #expect(converted.panel?.details?.strip.entries.prefix(4).map(\.text) == [
            "W1 22.7",
            "W2 22.7",
            "W3 22.7",
            "W4 23.9"
        ])
    }

    @Test("A fixed exercise shows the same load every week but the deload")
    func weekStrip_fixed_staysAtTheStartLoad() throws {
        var screen = try DayScreen(DayEditorFixtures.seedInput(dayIndex: ProgramFixtures.DayIndex.lowerA))
        try screen.open("3B")
        #expect(try screen.details().strip.text
            == "W1 160 · W2 160 · W3 160 · W4 160 · W5 160 · W6 160 · W7 160 · W8 135 (deload)")
    }

    @Test("The strip has one entry for each week of the block and follows an edit of the start load")
    func weekStrip_followsTheBlockAndTheStartLoad() throws {
        var screen = try Self.seedScreen(open: "1")
        screen.input.program = ProgramEditing.addWeek(screen.input.program, id: WeekID(Fixtures.uuid(990)))
        #expect(try screen.details().strip.entries.count == 9)
        try screen.step("START LOAD", .upward)
        #expect(try screen.details().strip.entries.prefix(3).map(\.text) == ["W1 185", "W2 190", "W3 195"])
        #expect(try screen.details().week.line == "5 × 5 @ 185 lb · RPE 8")
    }
}
