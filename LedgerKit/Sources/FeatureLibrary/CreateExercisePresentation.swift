import Foundation
import LedgerDomain

/// The exercise sheet's words and choices (F12 S3), from the store's draft: every chip of every field in the Domain's
/// order, the chosen ones selected, and the problem Save found under the field it concerns. Every text is
/// `LibraryCopy`'s; the name is the lifter's, shown as typed.
nonisolated enum CreateExercisePresentation {
    static func make(_ input: CreateExerciseInput) -> CreateExerciseModel {
        let draft = input.draft
        let locale = input.locale
        return CreateExerciseModel(
            title: input.isEdit ? LibraryCopy.editExercise : LibraryCopy.newExercise,
            cancel: LibraryCopy.cancel,
            name: CreateExerciseModel.Name(
                label: LibraryCopy.nameField,
                text: draft.name,
                problem: input.problem.flatMap(nameProblem)
            ),
            groups: [
                group(.equipment, LibraryCopy.equipmentRow, Equipment.allCases, locale: locale) { equipment in
                    Choice(LibraryCopy.equipment(equipment), equipment == draft.equipment, .setEquipment(equipment))
                },
                group(.primaryMuscle, LibraryCopy.primaryMuscleField, MuscleGroup.allCases, locale: locale) { muscle in
                    Choice(LibraryCopy.muscle(muscle), muscle == draft.primaryMuscle, .setPrimaryMuscle(muscle))
                },
                // The primary muscle has no chip here: it is never a secondary one too (N15).
                group(
                    .secondaryMuscles,
                    LibraryCopy.secondaryMusclesField,
                    MuscleGroup.allCases.filter { $0 != draft.primaryMuscle },
                    locale: locale
                ) { muscle in
                    let isOn = draft.secondaryMuscles.contains(muscle)
                    return Choice(LibraryCopy.muscle(muscle), isOn, .setSecondaryMuscle(muscle, isOn: !isOn))
                },
                group(.pattern, LibraryCopy.patternField, MovementPattern.allCases, locale: locale) { pattern in
                    Choice(LibraryCopy.pattern(pattern), pattern == draft.pattern, .setPattern(pattern))
                }
            ],
            foot: CreateExerciseModel.Foot(
                title: LibraryCopy.save,
                problem: input.problem.flatMap(footProblem),
                action: input.isSaving ? nil : .save
            )
        )
    }

    /// One chip as a field writes it: its title, whether it is chosen and what its tap does.
    private struct Choice {
        let title: String
        let isSelected: Bool
        let action: CreateExerciseAction

        init(_ title: String, _ isSelected: Bool, _ action: CreateExerciseAction) {
            self.title = title
            self.isSelected = isSelected
            self.action = action
        }
    }

    /// One field's chips, each with its title, whether it is chosen and what its tap does.
    private static func group<Value>(
        _ field: CreateExerciseModel.Field,
        _ title: String,
        _ values: [Value],
        locale: Locale,
        chip: (Value) -> Choice
    ) -> CreateExerciseModel.ChipGroup {
        CreateExerciseModel.ChipGroup(
            id: field,
            title: title,
            allowsMany: field == .secondaryMuscles,
            chips: values.enumerated().map { place, value in
                let made = chip(value)
                return CreateExerciseModel.Chip(
                    id: place,
                    title: made.title,
                    spokenLabel: LibraryCopy.spokenChip(row: title, title: made.title, locale: locale),
                    isSelected: made.isSelected,
                    action: made.action
                )
            }
        )
    }

    /// The line under the name field: a rule of the name that Save found broken.
    private static func nameProblem(_ problem: CreateExerciseProblem) -> String? {
        switch problem {
        case .invalid(.blankName): LibraryCopy.enterAName
        case .invalid(.nameLength): LibraryCopy.nameLength
        case .invalid(.controlCharacter): LibraryCopy.nameHasControlCharacter
        case .invalid(.duplicateName): LibraryCopy.duplicateName
        case .invalid(.primaryAmongSecondaries), .failed: nil
        }
    }

    /// The line over Save: a save that failed. The muscles' rule cannot be broken from the sheet, which offers no
    /// chip for the primary muscle among the secondary ones; were it broken, the save did not go through.
    private static func footProblem(_ problem: CreateExerciseProblem) -> String? {
        switch problem {
        case .failed, .invalid(.primaryAmongSecondaries): LibraryCopy.saveFailed
        case .invalid: nil
        }
    }
}
