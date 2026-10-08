@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 criterion 12: the wording of the exercise library's copy, through its copy file.
nonisolated extension ProgramCopyTests {
    @Test("The library's plain texts are the brief's, word for word")
    func picker_plainTexts_areTheBriefs() {
        #expect(ProgramCopy.exerciseLibrary == "Exercise library")
        #expect(ProgramCopy.cancel == "Cancel")
        #expect(ProgramCopy.searchExercises == "Search exercises")
        #expect(ProgramCopy.allChip == "All")
        #expect(ExerciseSearch.MuscleFilter.allCases.map(ProgramCopy.muscleFilter) == [
            "Chest", "Back", "Shoulders", "Legs", "Arms"
        ])
        #expect(ProgramCopy.alreadyInThisDay == "already in this day")
        #expect(ProgramCopy.nothingMatches == "Nothing matches that filter.")
        #expect(ProgramCopy.clearFilters == "Clear filters")
        #expect(ProgramCopy.selectExercisesToAdd == "Select exercises to add")
    }

    @Test("The library's button counts its exercises, with the singular for one")
    func picker_addExercises_hasOneAndOther() {
        #expect([1, 2, 3, 12].map { ProgramCopy.addExercises($0, locale: Self.english) } == [
            "Add 1 exercise", "Add 2 exercises", "Add 3 exercises", "Add 12 exercises"
        ])
        #expect(ProgramCopy.addExercises(1234, locale: Locale(identifier: "de_DE")) == "Add 1.234 exercises")
    }

    @Test("The library's texts the brief does not give read as the notes list them")
    func picker_writtenTexts_areTheNotes() {
        #expect(ProgramCopy.muscleRow == "Muscle")
        #expect(ProgramCopy.equipmentRow == "Equipment")
        #expect(ProgramCopy.spokenChip(row: "Muscle", title: "Chest", locale: Self.english) == "Muscle: Chest")
        #expect(MuscleGroup.allCases.map(ProgramCopy.muscle) == [
            "Chest", "Back", "Shoulders", "Quads", "Hamstrings", "Glutes", "Calves", "Biceps", "Triceps", "Forearms",
            "Core"
        ])
    }

    @Test("A muscle chip that stands for one group reads as that group does on a row")
    func picker_chipAndRow_shareTheGroupsName() {
        for filter in ExerciseSearch.MuscleFilter.allCases where filter.groups.count == 1 {
            #expect(filter.groups.map(ProgramCopy.muscle) == [ProgramCopy.muscleFilter(filter)])
        }
    }
}
