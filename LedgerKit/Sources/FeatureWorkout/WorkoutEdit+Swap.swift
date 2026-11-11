import Foundation
import LedgerDomain

/// What "Use" on the swap sheet comes to (F10 S8b, criteria 18 and 19): one event. In a file of its own for
/// the plan's length.
nonisolated extension WorkoutEditPlan {
    /// One `exerciseSwapped` that brings the choice's replacement, as the sheet showed it, and the toggle.
    /// It is planned at its turn, on the newest workout: if the exercise at that place is no longer the one the
    /// sheet was opened for, or now has a set logged (S8 ruling Q2), or the place is gone, it comes to
    /// nothing. The selection is left as it was: no set of the exercise is logged, so its shown row is still
    /// the one the lifter saw.
    mutating func swap(
        _ choice: SwapChoice,
        at exerciseIndex: Int,
        alsoUpdateProgram: Bool,
        in state: WorkoutState
    ) {
        guard state.exercises.indices.contains(exerciseIndex) else {
            return
        }
        let exercise = state.exercises[exerciseIndex]
        guard exercise.exerciseID == choice.replacing, WorkoutPresentation.canSwap(exercise) else {
            return
        }
        events.append(.exerciseSwapped(
            exerciseIndex: exerciseIndex,
            exerciseID: choice.exerciseID,
            name: choice.name,
            alsoUpdateProgram: alsoUpdateProgram,
            replacement: choice.replacement
        ))
    }
}
