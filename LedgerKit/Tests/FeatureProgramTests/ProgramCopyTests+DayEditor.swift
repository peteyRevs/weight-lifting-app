@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 criterion 7: the wording of the Day editor's and the slot editor's copy, through the copy files.
nonisolated extension ProgramCopyTests {
    @Test("The Day editor's plain texts are the brief's, word for word")
    func dayEditor_plainTexts_areTheBriefs() {
        #expect(ProgramCopy.backToProgram == "Program")
        #expect(ProgramCopy.done == "Done")
        #expect(ProgramCopy.supersetMark == "SUPERSET")
        #expect(ProgramCopy.fixed == "Fixed")
        #expect(ProgramCopy.dropMark == "drop")
        #expect(ProgramCopy.noRest == "no rest")
        #expect(ProgramCopy.addExerciseFromLibrary == "+ Add exercise from library")
        #expect(ProgramCopy.delete == "Delete")
        #expect(ProgramCopy.cancel == "Cancel")
        #expect(ProgramCopy.heldMark == "HELD")
        #expect([
            ProgramCopy.setsLabel, ProgramCopy.repsLabel, ProgramCopy.repFloorLabel, ProgramCopy.topOfRangeLabel,
            ProgramCopy.startLoadLabel, ProgramCopy.targetRPELabel, ProgramCopy.rest
        ] == ["SETS", "REPS", "REP FLOOR", "TOP OF RANGE", "START LOAD", "TARGET RPE", "REST"])
        #expect(ProgramCopy.progressionTitle == "PROGRESSION")
        #expect(Progression.allCases.map(ProgramCopy.progression) == ["Linear", "Double", "Fixed"])
        #expect(ProgramCopy.dropSet == "Drop set")
        #expect(ProgramCopy.dropSetNoteOff == "One extra set at −15% after the last working set.")
        #expect(ProgramCopy.dropSetNoteOn == "One extra set at −15%, straight after the last working set.")
        #expect(ProgramCopy.breakOut == "Break out")
        #expect(ProgramCopy.supersetWithNext == "Superset with next")
        #expect([ProgramCopy.moveUp, ProgramCopy.moveDown, ProgramCopy.remove] == ["Move up", "Move down", "Remove"])
    }

    @Test("The Day editor's texts the brief does not give read as the notes list them")
    func dayEditor_writtenTexts_areTheNotes() {
        let locale = Self.english
        #expect(ProgramCopy.dayName == "Day name")
        #expect(ProgramCopy.deleteDay == "Delete day")
        #expect(ProgramCopy.supersetSpoken == "Superset")
        #expect(ProgramCopy.spokenRow(index: "4A", name: "Lat Pulldown", locale: locale) == "4A, Lat Pulldown")
        #expect(ProgramCopy.stripHeldWeek(5, load: "190", locale: locale) == "W5 190 (held)")
        #expect([
            ProgramCopy.setsSpoken, ProgramCopy.repsSpoken, ProgramCopy.repFloorSpoken, ProgramCopy.topOfRangeSpoken,
            ProgramCopy.startLoadSpoken, ProgramCopy.targetRPESpoken, ProgramCopy.restSpoken
        ] == ["Sets", "Reps", "Rep floor", "Top of range", "Start load", "Target RPE", "Rest"])
    }

    @Test("Each kind of equipment has its name")
    func equipment_namesEachKind() {
        #expect(Equipment.allCases.map(ProgramCopy.equipment) == [
            "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Band"
        ])
    }

    @Test("The Day editor's texts with a value read as the brief writes them")
    func dayEditor_textsWithValues_areTheBriefs() {
        let locale = Self.english
        #expect(ProgramCopy.dayPosition(2, of: 4, locale: locale) == "DAY 2 OF 4")
        #expect(ProgramCopy.restAfter("B", locale: locale) == "rest after B")
        #expect(ProgramCopy.slotIndex(4, letter: "A", locale: locale) == "4A")
        #expect(ProgramCopy.slotIndex(4, letter: "", locale: locale) == "4")
        #expect(ProgramCopy.stepAWeek("2.5", locale: locale) == "+2.5/wk")
        #expect(ProgramCopy.repRange(10, 12, locale: locale) == "Reps 10–12")
        #expect(ProgramCopy.rpe("8.5", locale: locale) == "RPE 8.5")
        #expect(ProgramCopy.restOf("2:30", locale: locale) == "2:30 rest")
        #expect(ProgramCopy.scheme(sets: 5, reps: 5, locale: locale) == "5×5")
        #expect(ProgramCopy.deleteTitle("Lower B", locale: locale) == "Delete Lower B?")
        #expect(ProgramCopy.stripWeek(4, load: "52.5", locale: locale) == "W4 52.5")
        #expect(ProgramCopy.stripDeloadWeek(8, load: "240", locale: locale) == "W8 240 (deload)")
    }

    @Test("A line that prints a load has its wording in pounds and in kilograms")
    func loads_haveBothUnits() {
        let locale = Self.english
        #expect(Units.allCases.map { ProgramCopy.load("52.5", units: $0, locale: locale) } == ["52.5 lb", "52.5 kg"])
        #expect(Units.allCases.map { ProgramCopy.target(sets: 5, reps: 5, load: "185", units: $0, locale: locale) }
            == ["5 × 5 @ 185 lb", "5 × 5 @ 185 kg"])
        #expect(Units.allCases.map { ProgramCopy.linearNote(step: "5", start: "185", units: $0, locale: locale) } == [
            "Adds 5 lb a week from 185 lb. A week with a missed set holds the load.",
            "Adds 5 kg a week from 185 kg. A week with a missed set holds the load."
        ])
        #expect(Units.allCases.map {
            ProgramCopy.doubleNote(top: 10, step: "5", floor: 8, units: $0, locale: locale)
        } == [
            "Adds a rep each week up to 10, then +5 lb back at 8.",
            "Adds a rep each week up to 10, then +5 kg back at 8."
        ])
        #expect(Units.allCases.map { ProgramCopy.fixedNote(start: "160", units: $0, locale: locale) } == [
            "Stays at 160 lb for the whole block.", "Stays at 160 kg for the whole block."
        ])
    }

    @Test("The Day editor's counted texts take the singular with one")
    func dayEditor_countedTexts_haveOneAndOther() {
        let locale = Self.english
        #expect([1, 2, 3].map { ProgramCopy.backToBack($0, locale: locale) } == [
            "1 exercise back to back", "2 exercises back to back", "3 exercises back to back"
        ])
        #expect([0, 1, 8].map { ProgramCopy.scheduledInWeeks($0, locale: locale) } == [
            "It's scheduled in 0 weeks. Those days become rest.",
            "It's scheduled in 1 week. Those days become rest.",
            "It's scheduled in 8 weeks. Those days become rest."
        ])
    }
}
