import Foundation
import LedgerDomain

nonisolated extension WorkoutPresentation {
    /// Whether "Swap exercise" is offered for `exercise`: only while none of its sets is logged (S8 ruling
    /// Q2). The engine swaps the whole exercise, so a set already logged would be stored under the
    /// replacement's name, a false "Last" and a false baseline for records. Un-logging the set offers it again.
    static func canSwap(_ exercise: WorkoutExercise) -> Bool {
        !exercise.sets.contains { $0.isDone }
    }

    /// Whether the place `index` of `state` still holds `exerciseID` and it can be swapped: what the sheet was
    /// opened for is still there, with no set logged. The one check of the card's button, of the sheet's read,
    /// of the sheet staying up and of "Use" at its turn (review N2).
    static func canSwap(_ exerciseID: ExerciseID, at index: Int, in state: WorkoutState) -> Bool {
        state.exercises.indices.contains(index) && state.exercises[index].exerciseID == exerciseID
            && canSwap(state.exercises[index])
    }

    /// Whether `exerciseID` stands at a place of `state` other than `index` (Q9: a swap never puts one exercise
    /// in the workout twice).
    static func holds(_ exerciseID: ExerciseID, besides index: Int, in state: WorkoutState) -> Bool {
        state.exercises.indices.contains { $0 != index && state.exercises[$0].exerciseID == exerciseID }
    }

    /// The swap sheet of `swap` over `state` (criteria 14 to 16, 23 and 24). The rows' numbers are the ones
    /// "Use" applies, formatted by the Domain in the workout's units; the switch is drawn only where it can
    /// change something, an exercise from a program's slot, and opens as the store holds it.
    static func swapSheet(_ swap: SwapState, in state: WorkoutState, locale: Locale) -> SwapSheetModel {
        var message: String?
        var choices: [SwapChoice] = []
        switch swap.alternatives {
        case .idle, .loading:
            break
        case let .loaded(loaded):
            choices = loaded
            message = loaded.isEmpty ? WorkoutCopy.noAlternatives : nil
        case .failed:
            message = WorkoutCopy.couldNotLoadAlternatives
        }
        let exercise = state.exercises.indices.contains(swap.exerciseIndex) ? state.exercises[swap.exerciseIndex] : nil
        let hasSlot = state.source != nil && exercise?.slotID != nil
        return SwapSheetModel(
            title: WorkoutCopy.swapExercise,
            cancel: WorkoutCopy.cancel,
            line: WorkoutCopy.sameMovementPattern,
            message: message,
            toggle: hasSlot && !choices.isEmpty
                ? SwapSheetModel.Toggle(label: WorkoutCopy.alsoUpdateProgram, isOn: swap.alsoUpdateProgram)
                : nil,
            rows: choices.map { choice in
                SwapSheetModel.Row(
                    id: choice.exerciseID,
                    name: choice.name,
                    detail: detail(of: choice.replacement, units: state.units, locale: locale),
                    use: WorkoutCopy.use,
                    choose: .swap(
                        exerciseIndex: swap.exerciseIndex,
                        choice: choice,
                        alsoUpdateProgram: swap.alsoUpdateProgram
                    )
                )
            }
        )
    }

    /// "Dumbbell · 15 lb": the equipment, then the load the sets will take; the equipment alone when that
    /// load is zero, as for a push-up (Q7).
    private static func detail(of replacement: SwappedExercise, units: Units, locale: Locale) -> String {
        let equipment = WorkoutCopy.equipment(replacement.equipment)
        guard replacement.load > .zero else {
            return equipment
        }
        return WorkoutCopy.equipmentAndLoad(
            equipment,
            load: replacement.load.formatted(in: units),
            units: units,
            locale: locale
        )
    }
}
