import Foundation
import LedgerDomain

/// A row of "REMAINING", or a superset's legend row, as `WorkoutEditPlan` answers it (F10 S5, S9). In a file
/// of its own for the plan's length.
nonisolated extension WorkoutEditPlan {
    /// The exercise becomes the shown one, at its first set that is not logged. With none left it is shown
    /// with no row selected, and the engine's cursor stays where it is: "REMAINING" lists such an exercise
    /// only when the page shows no exercise at all (criterion 16), and its card then offers "+ Add set".
    ///
    /// A superset's member is shown at its first row not logged in the block's display order (rule 20), as
    /// the cursor and the block's shown row take them: a set added after a drop set comes before it
    /// (F10-S9-G2-1). A legend tap inside the block on screen changes nothing when its member has no row left
    /// (review SF1), or already holds the shown row (N5): the shown row, a chosen one included, and the
    /// header stay as they were. A tap from "REMAINING", which lists such a member only when nothing is shown,
    /// still shows its block.
    mutating func jump(to exerciseIndex: Int, in state: WorkoutState) {
        guard state.exercises.indices.contains(exerciseIndex) else {
            return
        }
        let sets = state.exercises[exerciseIndex].sets
        let block = WorkoutPresentation.superset(holding: exerciseIndex, in: state.exercises)
        let order = block.map { block in
            SupersetRounds.displayOrder(block: block, exercises: state.exercises)
                .filter { $0.exerciseIndex == exerciseIndex }.map(\.setIndex)
        } ?? Array(sets.indices)
        let open = order.first { !sets[$0].isDone }
        let shown = WorkoutPresentation.shownExercise(of: state, selection: selection)
        if let block, let shown, block.exerciseIndices.contains(shown), open == nil || shown == exerciseIndex {
            return
        }
        guard let setIndex = open else {
            selection = WorkoutSelection(exerciseIndex: exerciseIndex, setID: nil)
            return
        }
        events.append(.exerciseSelected(exerciseIndex: exerciseIndex, setIndex: setIndex))
        selection = WorkoutSelection(exerciseIndex: exerciseIndex, setID: sets[setIndex].id)
    }
}
