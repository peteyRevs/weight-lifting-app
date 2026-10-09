@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// What the property suite holds a model to, part by part.
nonisolated extension ExercisePickerPresentationPropertyTests {
    /// The list is `ExerciseSearch.filtered`'s, with equipment that has no chip read as none; the empty state
    /// stands exactly when the list is empty.
    static func checkList(_ model: ExercisePickerModel, _ input: ExercisePickerInput) {
        let hasChip = input.equipment.map(ExercisePickerPresentation.equipmentChips.contains) ?? false
        let expected = ExerciseSearch.filtered(
            input.exercises,
            query: input.query,
            muscle: input.muscle,
            equipment: hasChip ? input.equipment : nil
        )
        let isTheDomains = model.rows.map(\.id) == expected.map(\.id)
        #expect(isTheDomains, "the list is not ExerciseSearch.filtered's")
        #expect((model.empty != nil) == expected.isEmpty)
        #expect(model.search.query == input.query)
        #expect(!model.title.isEmpty && !model.cancel.title.isEmpty && !model.search.placeholder.isEmpty)
        if let empty = model.empty {
            #expect(!empty.message.isEmpty && !empty.clear.title.isEmpty)
        }
    }

    /// Six chips a row, exactly one selected: the one whose action sets the filter the input holds.
    static func checkChips(_ model: ExercisePickerModel, _ input: ExercisePickerInput) {
        for row in [model.muscles, model.equipment] {
            #expect(row.chips.count == 6)
            #expect(row.chips.count(where: \.isSelected) == 1, "\(row.titles)")
            #expect(row.chips.map(\.id) == Array(row.chips.indices))
            #expect(row.chips.allSatisfy { !$0.title.isEmpty && $0.spokenLabel.contains($0.title) })
            #expect(row.chips.allSatisfy { $0.spokenLabel.hasPrefix(row.spokenLabel) })
            #expect(Set(row.chips.map(\.spokenLabel)).count == 6)
        }
        #expect(model.muscles.chips.first(where: \.isSelected)?.action == .setMuscle(input.muscle))
        let selected = model.equipment.chips.first(where: \.isSelected)?.action
        #expect(selected == .setEquipment(input.equipment) || selected == .setEquipment(nil))
        #expect(Set(model.muscles.chips.map(\.spokenLabel)).isDisjoint(with: model.equipment.chips.map(\.spokenLabel)))
    }

    /// Each row is its exercise's: the name, the line, the day's mark, the pick and its place.
    static func checkRows(_ model: ExercisePickerModel, _ input: ExercisePickerInput) {
        let picks = expectedPicks(input)
        #expect(Set(model.rows.map(\.id)).count == model.rows.count)
        for row in model.rows {
            let exercise = input.exercises.first { $0.id == row.id }
            #expect(row.name == exercise?.name)
            #expect(!row.detail.isEmpty && row.detail.components(separatedBy: " · ").count == 2)
            #expect((row.inDayMark != nil) == input.dayExercises.contains(row.id))
            #expect(row.line == [row.detail, row.inDayMark].compactMap(\.self).joined(separator: " · "))
            let place = picks.firstIndex(of: row.id)
            #expect(row.isPicked == (place != nil))
            #expect(row.pickMark == place.map { ($0 + 1).formatted(.number.locale(input.locale)) })
            #expect(row.action == .setPicked(!row.isPicked, exercise: row.id))
        }
    }

    /// The foot adds the picks that count, and is disabled when there is none.
    static func checkFoot(_ model: ExercisePickerModel, _ input: ExercisePickerInput) {
        let picks = expectedPicks(input)
        #expect(model.foot.action == (picks.isEmpty ? nil : .add(picks)))
        #expect(!model.foot.title.isEmpty)
        let count = picks.count.formatted(.number.locale(input.locale))
        #expect(model.foot.title.contains(count) == !picks.isEmpty, "\(model.foot.title)")
    }
}
