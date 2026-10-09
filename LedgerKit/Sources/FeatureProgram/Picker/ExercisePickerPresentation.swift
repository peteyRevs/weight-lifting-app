import Foundation
import LedgerDomain

/// The exercise library sheet's logic and its words: one pure function from an `ExercisePickerInput` to the
/// `ExercisePickerModel` the views draw.
///
/// It reads its input and nothing else, and filters and sorts nothing itself: the list is
/// `ExerciseSearch.filtered`'s, in its order. It builds no slot either: the foot's action names the picked
/// exercises, and the store turns them into slots with `DayEditing.newSlot`. Every text comes from
/// `ProgramCopy`; an exercise's name is data.
nonisolated enum ExercisePickerPresentation {
    typealias Control = ExercisePickerModel.Control

    static let separator = ProgramPresentation.separator

    /// The muscle chips after "All", in order: the Domain's list of them.
    static let muscleChips = ExerciseSearch.MuscleFilter.allCases
    /// The equipment chips after "All", in order (Pete's decision 3, default B). Kettlebell and band have
    /// no chip: those exercises are found under "All" and by name.
    static let equipmentChips: [Equipment] = [.barbell, .dumbbell, .cable, .machine, .bodyweight]

    static func make(_ input: ExercisePickerInput) -> ExercisePickerModel {
        // A kind of equipment that has no chip would filter the list with no chip selected.
        let equipment = input.equipment.flatMap { equipmentChips.contains($0) ? $0 : nil }
        let shown = ExerciseSearch.filtered(
            input.exercises,
            query: input.query,
            muscle: input.muscle,
            equipment: equipment
        )
        let picks = storedPicks(input)
        let locale = input.locale
        return ExercisePickerModel(
            title: ProgramCopy.exerciseLibrary,
            cancel: Control(title: ProgramCopy.cancel, action: .cancel),
            search: ExercisePickerModel.Search(placeholder: ProgramCopy.searchExercises, query: input.query),
            muscles: chipRow(
                ProgramCopy.muscleRow,
                all: ChipSpec(isSelected: input.muscle == nil, action: .setMuscle(nil)),
                muscleChips.map {
                    ChipSpec(ProgramCopy.muscleFilter($0), isSelected: $0 == input.muscle, action: .setMuscle($0))
                },
                locale: locale
            ),
            equipment: chipRow(
                ProgramCopy.equipmentRow,
                all: ChipSpec(isSelected: equipment == nil, action: .setEquipment(nil)),
                equipmentChips.map {
                    ChipSpec(ProgramCopy.equipment($0), isSelected: $0 == equipment, action: .setEquipment($0))
                },
                locale: locale
            ),
            content: shown.isEmpty
                ? .nothingMatches(ExercisePickerModel.Empty(
                    message: ProgramCopy.nothingMatches,
                    clear: Control(title: ProgramCopy.clearFilters, action: .clearFilters)
                ))
                : .rows(shown.map { row($0, input: input, picks: picks) }),
            foot: foot(picks: picks, locale: locale)
        )
    }

    /// The picks that count, in the order picked: each exercise once, at its first place, and only those
    /// still stored.
    static func storedPicks(_ input: ExercisePickerInput) -> [ExerciseID] {
        let stored = Set(input.exercises.map(\.id))
        var seen: Set<ExerciseID> = []
        return input.picks.filter { stored.contains($0) && seen.insert($0).inserted }
    }

    /// A chip before it has its place in a row: its title ("All" unless another is given), whether it is the
    /// one selected, and the filter it sets.
    struct ChipSpec {
        let title: String
        let isSelected: Bool
        let action: ExercisePickerAction

        init(_ title: String = ProgramCopy.allChip, isSelected: Bool, action: ExercisePickerAction) {
            self.title = title
            self.isSelected = isSelected
            self.action = action
        }
    }

    /// One row of chips: "All" first, then `chips` in their order.
    static func chipRow(
        _ name: String,
        all: ChipSpec,
        _ chips: [ChipSpec],
        locale: Locale
    ) -> ExercisePickerModel.ChipRow {
        ExercisePickerModel.ChipRow(
            spokenLabel: name,
            chips: ([all] + chips).enumerated().map { place, chip in
                ExercisePickerModel.Chip(
                    id: place,
                    title: chip.title,
                    spokenLabel: ProgramCopy.spokenChip(row: name, title: chip.title, locale: locale),
                    isSelected: chip.isSelected,
                    action: chip.action
                )
            }
        )
    }

    /// An exercise's row: "Machine · Back", with " · already in this day" when the day holds it, and its
    /// place among the picks when it is picked.
    static func row(_ exercise: Exercise, input: ExercisePickerInput, picks: [ExerciseID]) -> ExercisePickerModel.Row {
        let detail = [ProgramCopy.equipment(exercise.equipment), ProgramCopy.muscle(exercise.primaryMuscle)]
            .joined(separator: separator)
        let mark = input.dayExercises.contains(exercise.id) ? ProgramCopy.alreadyInThisDay : nil
        let line = [detail, mark].compactMap(\.self).joined(separator: separator)
        let place = picks.firstIndex(of: exercise.id)
        return ExercisePickerModel.Row(
            id: exercise.id,
            name: exercise.name,
            detail: detail,
            inDayMark: mark,
            line: line,
            isPicked: place != nil,
            pickMark: place.map { ($0 + 1).formatted(.number.locale(input.locale)) },
            action: .setPicked(place == nil, exercise: exercise.id)
        )
    }

    /// "Select exercises to add" and no action with no pick; else "Add 3 exercises" and the picks.
    static func foot(picks: [ExerciseID], locale: Locale) -> ExercisePickerModel.Foot {
        guard !picks.isEmpty else {
            return ExercisePickerModel.Foot(title: ProgramCopy.selectExercisesToAdd, action: nil)
        }
        return ExercisePickerModel.Foot(
            title: ProgramCopy.addExercises(picks.count, locale: locale),
            action: .add(picks)
        )
    }
}
