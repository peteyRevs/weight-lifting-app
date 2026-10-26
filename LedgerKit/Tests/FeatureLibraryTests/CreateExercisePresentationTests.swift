@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S3: the exercise sheet's words and choices (`CreateExercisePresentation`), and the history's "Edit" for the
/// lifter's own exercise only (criterion 10), from fixed inputs.
@Suite("CreateExercisePresentation", .tags(.feature))
struct CreateExercisePresentationTests {
    static func model(
        _ draft: CustomExerciseDraft = CustomExerciseDraft(),
        isEdit: Bool = false
    ) -> CreateExerciseModel {
        CreateExercisePresentation.make(CreateExerciseInput(draft: draft, isEdit: isEdit, locale: Fixtures.locale))
    }

    @Test("The four fields, in order, under the brief's headings; only the secondary muscles allow many")
    func fields_inOrderWithTheirHeadings() {
        let model = Self.model()
        #expect(model.title == "New exercise" && model.cancel == "Cancel" && model.foot.title == "Save")
        #expect(model.name.label == "Name" && model.name.text.isEmpty && model.name.problem == nil)
        #expect(model.groups.map(\.title) == ["Equipment", "Primary muscle", "Secondary muscles", "Movement pattern"])
        #expect(model.groups.map(\.allowsMany) == [false, false, true, false])
        #expect(model.groups.map(\.chips.count) == [7, 11, 10, 10])
        #expect(Self.model(isEdit: true).title == "Edit exercise")
    }

    @Test("Every chip names its field to VoiceOver, and each field of one choice has exactly one chosen")
    func chips_spokenWithTheirField_oneChosen() {
        let model = Self.model(CreatePreviewData.filled)
        let equipment = model.groups[0].chips
        #expect(equipment.map(\.title) == [
            "Barbell",
            "Dumbbell",
            "Cable",
            "Machine",
            "Bodyweight",
            "Kettlebell",
            "Band"
        ])
        #expect(equipment.first?.spokenLabel == "Equipment: Barbell")
        #expect(model.groups[1].chips.first?.spokenLabel == "Primary muscle: Chest")
        #expect(model.groups[2].chips.first?.spokenLabel == "Secondary muscles: Back")
        #expect(model.groups[3].chips.map(\.title) == [
            "Horizontal push", "Horizontal pull", "Vertical push", "Vertical pull", "Squat", "Hinge", "Lunge", "Carry",
            "Isolation", "Core"
        ])
        for group in model.groups where !group.allowsMany {
            #expect(group.chips.count { $0.isSelected } == 1, "\(group.title)")
        }
        #expect(model.groups[2].chips.filter(\.isSelected).map(\.title) == ["Shoulders", "Triceps"])
    }

    @Test("A chip's action makes it what it is not: a single choice is set, a secondary muscle switched")
    func chips_carryTheirActions() {
        let model = Self.model(CreatePreviewData.filled)
        #expect(model.groups[0].chips[1].action == .setEquipment(.dumbbell))
        #expect(model.groups[1].chips[3].action == .setPrimaryMuscle(.quads))
        let shoulders = model.groups[2].chips.first { $0.title == "Shoulders" }
        let back = model.groups[2].chips.first { $0.title == "Back" }
        #expect(shoulders?.action == .setSecondaryMuscle(.shoulders, isOn: false))
        #expect(back?.action == .setSecondaryMuscle(.back, isOn: true))
        #expect(model.groups[3].chips.last?.action == .setPattern(.core))
        #expect(model.foot.action == .save)
    }

    @Test("Each problem has its line: the name's under the field, a failed save over Save")
    func problems_haveTheirLines() {
        let id = ExerciseID(Fixtures.uuid(902))
        let lines: [(CreateExerciseProblem, name: String?, foot: String?)] = [ // swiftlint:disable:this large_tuple
            (.invalid(.blankName), "Enter a name.", nil),
            (.invalid(.nameLength(41)), "Name must be 2–40 characters.", nil),
            (.invalid(.controlCharacter), "That name holds a character that can't be saved.", nil),
            (.invalid(.duplicateName(id)), "An exercise with that name already exists.", nil),
            (.invalid(.primaryAmongSecondaries), nil, "Couldn't save the exercise. Try again."),
            (.failed, nil, "Couldn't save the exercise. Try again.")
        ]
        for (problem, name, foot) in lines {
            let model = CreateExercisePresentation.make(CreateExerciseInput(
                draft: CustomExerciseDraft(),
                problem: problem,
                locale: Fixtures.locale
            ))
            #expect(model.name.problem == name && model.foot.problem == foot, "\(problem)")
        }
        let saving = CreateExercisePresentation.make(CreateExerciseInput(
            draft: CustomExerciseDraft(), isSaving: true, locale: Fixtures.locale
        ))
        #expect(saving.foot.action == nil)
    }

    @Test("10. The history of the lifter's own exercise has Edit; a catalog exercise's has none")
    func historyEdit_customOnly() throws {
        var input = try HistoryFixtures.input([])
        #expect(ExerciseHistoryPresentation.make(input).edit == nil)
        input.exercise = LibraryFixtures.custom
        #expect(ExerciseHistoryPresentation.make(input).edit == "Edit")
    }
}
