@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6: the panel under the open exercise, for the brief's criteria 8 and 9: the stepper fields, the
/// progression with its note, and the drop set. Each test taps a control of the model and reads the next
/// model. The weeks' prescriptions (criterion 7) are in `+Preview`.
@Suite("SlotEditorPresentation", .tags(.feature))
nonisolated struct SlotEditorPresentationTests {
    /// Upper A of the seed program with the exercise at `index` open.
    static func seedScreen(open index: String, weekIndex: Int = 0) throws -> DayScreen {
        var screen = try DayScreen(DayEditorFixtures.seedInput(weekIndex: weekIndex))
        try screen.open(index)
        return screen
    }

    /// One exercise, open.
    static func screen(_ slot: Slot, units: Units = .lb) throws -> DayScreen {
        var input = try DayEditorFixtures.input(slots: [slot], units: units)
        input.openSlot = slot.id
        return DayScreen(input)
    }

    // MARK: The fields

    @Test("A linear exercise has five fields with the brief's labels, its own values and the spoken labels")
    func fields_linear_areFive() throws {
        let details = try Self.seedScreen(open: "1").details()
        #expect(details.fieldLine == "SETS 5 · REPS 5 · START LOAD 180 lb · TARGET RPE 8 · REST 2:30")
        #expect(details.fields.map(\.spokenLabel) == ["Sets", "Reps", "Start load", "Target RPE", "Rest"])
        #expect(details.fields.map(\.kind) == [.sets, .reps, .startLoad, .rpe, .rest])
        // A field is identified by its kind, a chip by its progression.
        #expect(details.fields.map(\.id) == details.fields.map(\.kind))
        #expect(details.progression.chips.map(\.id) == Progression.allCases)
    }

    @Test("Under double progression reps read REP FLOOR and the top of the range has its own field")
    func fields_double_areSix() throws {
        let details = try Self.seedScreen(open: "2").details()
        #expect(details.fieldLine
            == "SETS 3 · REP FLOOR 10 · TOP OF RANGE 12 · START LOAD 50 lb · TARGET RPE 8 · REST 1:30")
        #expect(details.fields.map(\.spokenLabel) == [
            "Sets", "Rep floor", "Top of range", "Start load", "Target RPE", "Rest"
        ])
    }

    @Test("The fields show the slot's own numbers in a deload week, where the row shows the week's")
    func fields_deloadWeek_showTheSlotsOwn() throws {
        let screen = try Self.seedScreen(open: "1", weekIndex: 7)
        #expect(try screen.details().fieldLine == "SETS 5 · REPS 5 · START LOAD 180 lb · TARGET RPE 8 · REST 2:30")
        #expect(try screen.content().row("1").scheme == "4×5")
    }

    @Test("Reps raised to the top of the range push the top to reps + 1 (criterion 8)")
    func reps_raisedToTheTop_pushTheTop() throws {
        var screen = try Self.seedScreen(open: "2")
        try screen.step("REP FLOOR", .upward)
        #expect(try screen.details().fieldLine.contains("REP FLOOR 11 · TOP OF RANGE 12"))
        try screen.step("REP FLOOR", .upward)
        #expect(try screen.details().fieldLine.contains("REP FLOOR 12 · TOP OF RANGE 13"))
        try screen.step("REP FLOOR", .upward)
        #expect(try screen.details().fieldLine.contains("REP FLOOR 13 · TOP OF RANGE 14"))
        // The row follows: the range, and the week's reps.
        #expect(try screen.content().row("2").sub == "Dumbbell · Reps 13–14 · RPE 8 · 1:30 rest")
        #expect(try screen.content().row("2").scheme == "3×13")
    }

    @Test("The top of the range lowered to reps snaps back to reps + 1 (criterion 8)")
    func topOfRange_loweredToReps_snapsAbove() throws {
        var screen = try Self.seedScreen(open: "2")
        try screen.step("TOP OF RANGE", .downward)
        #expect(try screen.details().value("TOP OF RANGE") == "11")
        try screen.step("TOP OF RANGE", .downward, times: 3)
        #expect(try screen.details().fieldLine.contains("REP FLOOR 10 · TOP OF RANGE 11"))
    }

    @Test("Sets stay within 1 and 12, and a stepper at its limit still offers both directions (behaviour 11)")
    func sets_clampAtOneAndTwelve() throws {
        var screen = try Self.seedScreen(open: "1")
        try screen.step("SETS", .upward, times: 9)
        #expect(try screen.details().value("SETS") == "12")
        let atTheTop = screen.input.program
        try screen.step("SETS", .upward)
        let isHeld = screen.input.program == atTheTop
        #expect(isHeld, "+ at 12 sets changed the program")
        try screen.step("SETS", .downward, times: 14)
        #expect(try screen.details().value("SETS") == "1")
        try screen.step("SETS", .upward)
        #expect(try screen.details().value("SETS") == "2")
    }

    @Test("Target RPE moves by a half between 5 and 10")
    func rpe_stepsByHalves() throws {
        var screen = try Self.seedScreen(open: "1")
        try screen.step("TARGET RPE", .upward)
        #expect(try screen.details().value("TARGET RPE") == "8.5")
        try screen.step("TARGET RPE", .upward, times: 5)
        #expect(try screen.details().value("TARGET RPE") == "10")
        try screen.step("TARGET RPE", .downward, times: 12)
        #expect(try screen.details().value("TARGET RPE") == "5")
        try screen.step("TARGET RPE", .upward)
        #expect(try screen.details().value("TARGET RPE") == "5.5")
    }

    @Test("Rest moves by 15 s between 30 s and 5 min, and reads 45s, 2 min or 2:30")
    func rest_stepsByFifteenSeconds() throws {
        var screen = try Self.seedScreen(open: "1")
        try screen.step("REST", .downward, times: 2)
        #expect(try screen.details().value("REST") == "2 min")
        try screen.step("REST", .downward, times: 5)
        #expect(try screen.details().value("REST") == "45s")
        try screen.step("REST", .downward, times: 4)
        #expect(try screen.details().value("REST") == "30s")
        try screen.step("REST", .upward, times: 30)
        #expect(try screen.details().value("REST") == "5 min")
        #expect(try screen.content().row("1").sub == "Barbell · +5/wk · RPE 8 · 5 min rest")
    }

    @Test("The start load moves by the equipment's step in pounds and never goes below zero")
    func startLoad_pounds_stepsAndFloorsAtZero() throws {
        var screen = try Self.seedScreen(open: "2")
        try screen.step("START LOAD", .upward)
        #expect(try screen.details().value("START LOAD") == "52.5 lb")
        try screen.step("START LOAD", .downward, times: 2)
        #expect(try screen.details().value("START LOAD") == "47.5 lb")
        try screen.step("START LOAD", .downward, times: 30)
        #expect(try screen.details().value("START LOAD") == "0 lb")
        try screen.open("1")
        try screen.step("START LOAD", .upward)
        #expect(try screen.details().value("START LOAD") == "185 lb")
    }

    @Test("In kilograms the start load moves by 2.5, 1.25 and the kettlebell's 2, in exact decimals", arguments: [
        ("Barbell Bench Press", "80", ["82.5 kg", "85 kg"]),
        ("Incline DB Press", "22.5", ["23.75 kg", "25 kg"]),
        ("Kettlebell Row", "16", ["18 kg", "20 kg"])
    ])
    func startLoad_kilograms_stepsByTheUnitsStep(name: String, start: String, expected: [String]) throws {
        let exercise = try DayEditorFixtures.exercise(named: name)
        let load = try Weight.kilograms(#require(Decimal(string: start, locale: Locale(identifier: "en_US_POSIX"))))
        var screen = try Self.screen(DayEditorFixtures.slot(1, exercise.id, startLoad: load), units: .kg)
        #expect(try screen.details().value("START LOAD") == "\(start) kg")
        var seen: [String] = []
        for _ in expected {
            try screen.step("START LOAD", .upward)
            try seen.append(screen.details().value("START LOAD"))
        }
        #expect(seen == expected)
    }

    @Test("A load off the unit's steps goes to the next multiple on the side asked for (behaviour 10)")
    func startLoad_offTheSteps_goesToTheNextMultiple() throws {
        // 180 lb read in kilograms is 81.6.
        let slot = try DayEditorFixtures.slot(1, startLoad: .pounds(180))
        var raised = try Self.screen(slot, units: .kg)
        #expect(try raised.details().value("START LOAD") == "81.6 kg")
        try raised.step("START LOAD", .upward)
        #expect(try raised.details().value("START LOAD") == "82.5 kg")
        var lowered = try Self.screen(slot, units: .kg)
        try lowered.step("START LOAD", .downward)
        #expect(try lowered.details().value("START LOAD") == "80 kg")
    }
}
