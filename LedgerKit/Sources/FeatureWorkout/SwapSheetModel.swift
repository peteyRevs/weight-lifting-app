import Foundation
import LedgerDomain

/// "Swap exercise" (F10 S8b): the sheet the card's swap button opens. Every string is final and so is what
/// each row sends; the view decides nothing.
nonisolated struct SwapSheetModel: Equatable, Sendable {
    let title: String
    /// The sheet's cancel.
    let cancel: String
    /// "Same movement pattern.", under the title in every state.
    let line: String
    /// "Couldn't load alternatives." or "No alternatives for this exercise."; nil while the alternatives load
    /// and when there are rows.
    let message: String?
    /// "Also update program": nil while the alternatives load, when there is no row, and for an exercise that
    /// came from no program slot, where it could change nothing.
    let toggle: Toggle?
    /// At most `SwapAlternatives.limit`, best first; none while they load.
    let rows: [Row]

    nonisolated struct Toggle: Equatable, Sendable {
        let label: String
        let isOn: Bool
    }

    /// One alternative: its name, "Dumbbell · 15 lb" (the load its sets will take), "Use", and the edit the
    /// row sends, which carries those very numbers and the toggle as it stands.
    nonisolated struct Row: Equatable, Sendable, Identifiable {
        let id: ExerciseID
        let name: String
        let detail: String
        let use: String
        let choose: WorkoutEdit
    }
}

/// An alternative the sheet offers, as it was read for the exercise the sheet was opened for: the exercise,
/// and what it brings into the workout (`SwapAlternatives.replacement`), so that what the row shows is what
/// "Use" applies.
nonisolated struct SwapChoice: Equatable, Sendable {
    /// The exercise the sheet was opened for: the choice comes to nothing once its place holds another.
    let replacing: ExerciseID
    let exerciseID: ExerciseID
    let name: String
    let replacement: SwappedExercise
}

/// The swap sheet as the store holds it: the exercise it was opened for, by its place and its id, what was
/// read for it, and the toggle. It stays after the sheet goes down, so that the sheet keeps its rows while it
/// animates away; the next "Swap exercise" replaces it.
nonisolated struct SwapState: Sendable {
    let exerciseIndex: Int
    let exerciseID: ExerciseID
    var alternatives: Loadable<[SwapChoice]> = .loading
    var alsoUpdateProgram: Bool
}
