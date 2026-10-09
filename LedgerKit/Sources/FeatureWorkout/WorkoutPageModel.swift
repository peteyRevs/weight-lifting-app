import Foundation
import LedgerDesign
import LedgerDomain

/// What scrolls under the cover's header (F10 S5): the shown exercise's card and the exercises after it.
/// Every string is final; the views decide nothing.
nonisolated struct WorkoutPageModel: Equatable, Sendable {
    /// Nil when the workout shows no exercise: it has none, or its cursor names no row and nothing was
    /// chosen. "REMAINING" then lists every exercise, so each can still be reached.
    let card: ExerciseCardModel?
    /// Nil when no exercise comes after the shown one.
    let remaining: RemainingModel?
    /// False while a discard runs or the cover is closing: no control of the page answers.
    let isEnabled: Bool
}

/// The shown exercise (v2 "Active workout", with v1's TARGET line): its place, its name, what was
/// prescribed, what was done last time, and one row per set.
nonisolated struct ExerciseCardModel: Equatable, Sendable {
    /// The exercise's place in the workout, which every edit of the card names.
    let exerciseIndex: Int
    /// "Exercise 2 of 5".
    let eyebrow: String
    /// The exercise's name, as the workout holds it: data, not copy.
    let title: String
    /// "TARGET".
    let targetLabel: String
    /// "5 × 5 @ 185 lb · RPE 8".
    let target: String
    /// "Last".
    let lastLabel: String
    /// "Aug 12 · 5×5 @ 180 lb", as the Domain writes it, or "No history yet".
    let last: String
    /// "Repeat"; nil without a last workout, and then no button is drawn.
    let repeatLast: String?
    /// "#", "lb" or "kg", "reps".
    let columns: Columns
    let rows: [SetRowModel]
    /// The steppers under the shown row; nil when no row is shown (every set is logged, or there is none).
    let steppers: SteppersModel?
    /// "+ Add set".
    let addSet: String

    nonisolated struct Columns: Equatable, Sendable {
        let number: String
        let weight: String
        let reps: String
    }
}

/// One set's row, in the words `LedgerDesign.SetRow` takes.
nonisolated struct SetRowModel: Equatable, Sendable, Identifiable {
    let id: SetID
    /// "1", "2", … counting the rows that are not drop sets; "D" for a drop set.
    let label: String
    /// "185", "52.5": the weight in the workout's unit, as the Domain writes it.
    let weight: String
    let reps: String
    let state: SetRowState
    /// "Log set 2", or "Undo set 2" once logged: what the check will do.
    let checkLabel: String
    /// "Set 2, 185 pounds, 5 reps": what VoiceOver reads for the row.
    let summary: String
    /// What the check sends: the set logged, or un-logged once it is.
    let check: WorkoutEdit
}

/// The two steppers under the shown row: the step each moves by, and the row's values as VoiceOver reads
/// them after a step.
nonisolated struct SteppersModel: Equatable, Sendable {
    /// The row the steppers change.
    let setID: SetID
    /// "5 LB", "2.5 KG".
    let weightStep: String
    /// "1 REP".
    let repStep: String
    /// "185 pounds".
    let weight: String
    /// "5 reps".
    let reps: String
}

/// "REMAINING": the exercises after the shown one, each a way to jump to it.
nonisolated struct RemainingModel: Equatable, Sendable {
    let title: String
    let rows: [Row]

    nonisolated struct Row: Equatable, Sendable, Identifiable {
        /// The exercise's place in the workout.
        let exerciseIndex: Int
        let name: String
        /// "3 × 10": its rows, and the reps of the first.
        let scheme: String

        var id: Int {
            exerciseIndex
        }
    }
}
