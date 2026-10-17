@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 criterion 7: the two rows of filter chips.
nonisolated extension ExercisePickerPresentationTests {
    // MARK: Criterion 7: the chips

    @Test("The chips are the brief's ten, after All in each row, and All is selected at first")
    func chips_areTheBriefs() throws {
        let model = try ExercisePickerPresentation.make(Fixture.input())
        #expect(model.muscles.titles == "All, Chest, Back, Shoulders, Legs, Arms")
        #expect(model.equipment.titles == "All, Barbell, Dumbbell, Cable, Machine, Bodyweight")
        #expect(model.muscles.selected == ["All"])
        #expect(model.equipment.selected == ["All"])
        #expect(model.muscles.chips.map(\.id) == Array(0 ... 5))
        #expect(model.equipment.chips.map(\.id) == Array(0 ... 5))
    }

    @Test("Each chip's action names the filter it sets, the selected one's too")
    func chips_actionsNameTheirFilter() throws {
        let model = try ExercisePickerPresentation.make(Fixture.input(muscle: .legs, equipment: .cable))
        #expect(model.muscles.chips.map(\.action) == [
            .setMuscle(nil), .setMuscle(.chest), .setMuscle(.back), .setMuscle(.shoulders), .setMuscle(.legs),
            .setMuscle(.arms)
        ])
        #expect(model.equipment.chips.map(\.action) == [
            .setEquipment(nil), .setEquipment(.barbell), .setEquipment(.dumbbell), .setEquipment(.cable),
            .setEquipment(.machine), .setEquipment(.bodyweight)
        ])
        #expect(model.muscles.selected == ["Legs"])
        #expect(model.equipment.selected == ["Cable"])
    }

    @Test("A chip is spoken with its row's name, so that the two All chips differ")
    func chips_areSpokenWithTheirRow() throws {
        let model = try ExercisePickerPresentation.make(Fixture.input())
        #expect(model.muscles.spokenLabel == "Muscle")
        #expect(model.equipment.spokenLabel == "Equipment")
        #expect(model.muscles.chips.map(\.spokenLabel) == [
            "Muscle: All", "Muscle: Chest", "Muscle: Back", "Muscle: Shoulders", "Muscle: Legs", "Muscle: Arms"
        ])
        #expect(model.equipment.chips.map(\.spokenLabel) == [
            "Equipment: All", "Equipment: Barbell", "Equipment: Dumbbell", "Equipment: Cable", "Equipment: Machine",
            "Equipment: Bodyweight"
        ])
    }

    @Test("Choosing a chip moves the selection and narrows the list; choosing All widens it again")
    func chips_tapped_selectAndFilter() throws {
        var screen = try PickerScreen(Fixture.input())
        try screen.tapChip("Legs", in: \.muscles)
        #expect(screen.model.muscles.selected == ["Legs"])
        let legs = screen.model.rows
        let muscles = Set(legs.map(\.detail).compactMap { $0.components(separatedBy: " · ").last })
        #expect(muscles == ["Quads", "Hamstrings", "Glutes", "Calves"])
        try screen.tapChip("Bodyweight", in: \.equipment)
        #expect(screen.model.equipment.selected == ["Bodyweight"])
        #expect(screen.model.rows.count < legs.count)
        #expect(screen.model.rows.allSatisfy { $0.detail.hasPrefix("Bodyweight · ") })
        // The same chip again changes nothing: the action says what the filter becomes.
        let before = screen.model.names
        try screen.tapChip("Bodyweight", in: \.equipment)
        #expect(screen.model.names == before)
        try screen.tapChip("All", in: \.muscles)
        try screen.tapChip("All", in: \.equipment)
        #expect(screen.model.rows.count == 224)
    }

    @Test("The chips come from one list each: the muscles are the Domain's, the equipment the presentation's five")
    func chips_areBuiltFromOneListEach() throws {
        let model = try ExercisePickerPresentation.make(Fixture.input())
        #expect(model.muscles.chips.dropFirst().map(\.action) == ExerciseSearch.MuscleFilter.allCases.map {
            .setMuscle($0)
        })
        #expect(model.equipment.chips.dropFirst().map(\.action) == ExercisePickerPresentation.equipmentChips.map {
            .setEquipment($0)
        })
        #expect(ExercisePickerPresentation.equipmentChips == [.barbell, .dumbbell, .cable, .machine, .bodyweight])
    }

    @Test("Equipment that has no chip is read as All: one chip is selected, and the list is not narrowed")
    func equipmentWithNoChip_isReadAsAll() throws {
        for equipment in [Equipment.kettlebell, .band] {
            let model = try ExercisePickerPresentation.make(Fixture.input(equipment: equipment))
            #expect(model.equipment.selected == ["All"], "\(equipment)")
            #expect(model.rows.count == 224, "\(equipment)")
        }
    }
}
