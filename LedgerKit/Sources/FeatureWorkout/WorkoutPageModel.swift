import Foundation
import LedgerDesign
import LedgerDomain

/// What scrolls under the cover's header (F10 S5): the shown exercise's card, or its superset's block (F10
/// S9), and the other exercises with a set left. Every string is final; the views decide nothing.
nonisolated struct WorkoutPageModel: Equatable, Sendable {
    /// Nil when the workout shows no exercise: it has none, or its cursor names no row and nothing was
    /// chosen. "REMAINING" then lists every exercise, so each can still be reached.
    let content: Content?
    /// Nil when no exercise outside the shown card or block has a set left to log.
    let remaining: RemainingModel?
    /// False while a discard runs or the cover is closing: no control of the page answers.
    let isEnabled: Bool

    /// A solo exercise is drawn as its card; a member of a superset of more than one member as the block.
    nonisolated enum Content: Equatable, Sendable {
        case card(ExerciseCardModel)
        case block(SupersetBlockModel)
    }

    /// The shown card; nil while a block, or nothing, is shown.
    var card: ExerciseCardModel? {
        if case let .card(card) = content {
            return card
        }
        return nil
    }

    /// What is shown, by place: the card's exercise, or the block's first member (review SF2). It changes when
    /// another card or block is shown, and not when the current member changes inside a block.
    var shownPlace: Int? {
        card?.exerciseIndex ?? block?.legend.first?.exerciseIndex
    }

    /// The shown block; nil while a card, or nothing, is shown.
    var block: SupersetBlockModel? {
        if case let .block(block) = content {
            return block
        }
        return nil
    }
}

/// A superset drawn as one block (F10 S9; spec §3.7, v1's legend): the block's place, the round, one legend
/// row per member, the group's rest, the current member's "Last" and "Repeat", and every row of the block in
/// round order, labelled by member letter.
nonisolated struct SupersetBlockModel: Equatable, Sendable {
    /// "Superset · block 4 of 4".
    let eyebrow: String
    /// "Round 2 of 3", a heading.
    let title: String
    /// One row per member, in the block's order.
    let legend: [LegendRow]
    /// "Rest 1:15 after B".
    let restLine: String
    /// "Rest 1 minute, 15 seconds after B".
    let restLineSpoken: String
    /// The current member's "Last" and "Repeat" (ruling Q1); nil when every row of the block is logged.
    let current: CurrentMember?
    let columns: ExerciseCardModel.Columns
    /// In display order (rule 20): A1 B1 A2 B2 A3 B3 AD BD.
    let rows: [SetRowModel]
    /// Under the shown row, in that row's member's step and unit; nil with every row logged.
    let steppers: SteppersModel?
    /// "+ Add set", for the current member (ruling Q3).
    let addSet: String

    nonisolated struct LegendRow: Equatable, Sendable, Identifiable {
        /// The member's place in the workout, which a tap jumps to.
        let exerciseIndex: Int
        let exerciseID: ExerciseID
        /// "A", "B", … (rule 44).
        let letter: String
        let name: String
        /// "3 × 12 @ 100 lb": the target's sets, reps and load, without RPE.
        let target: String
        /// The member that holds the shown row.
        let isCurrent: Bool
        /// "Swap Lat Pulldown": the swap button's spoken name; nil once a set of the member is logged, and
        /// while the page answers nothing, and then no button is drawn.
        let swap: String?
        /// "A, Lat Pulldown, 3 × 12 @ 100 lb": what VoiceOver reads for the row.
        let spoken: String

        var id: Int {
            exerciseIndex
        }
    }

    nonisolated struct CurrentMember: Equatable, Sendable {
        let exerciseIndex: Int
        /// "Last".
        let lastLabel: String
        /// "Aug 12 · 3×12 @ 95 lb", or "No history yet".
        let last: String
        /// "Repeat"; nil without a last workout.
        let repeatLast: String?
    }
}

/// The shown exercise (v2 "Active workout", with v1's TARGET line): its place, its name, what was
/// prescribed, what was done last time, and one row per set.
nonisolated struct ExerciseCardModel: Equatable, Sendable {
    /// The exercise's place in the workout, which every edit of the card names.
    let exerciseIndex: Int
    /// The exercise at that place, which "Swap exercise" names with its place (F10 S8b, review SF1).
    let exerciseID: ExerciseID
    /// "Exercise 2 of 5".
    let eyebrow: String
    /// The exercise's name, as the workout holds it: data, not copy.
    let title: String
    /// "Swap exercise", the round button beside the name; nil once a set of the exercise is logged (F10 S8b,
    /// ruling Q2) and while the page answers nothing (review N6), and then no button is drawn.
    let swap: String?
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
    /// The place of the row's exercise: a block's rows name different members (F10 S9).
    let exerciseIndex: Int
    /// "1", "2", … counting the rows that are not drop sets; "D" for a drop set. In a block the member's
    /// letter comes first: "A1", "BD".
    let label: String
    /// "185", "52.5": the weight in the workout's unit, as the Domain writes it.
    let weight: String
    let reps: String
    let state: SetRowState
    /// "Log set 2", or "Undo set 2" once logged: what the check will do.
    let checkLabel: String
    /// "Set 2, 185 pounds, 5 reps", in a block "Lat Pulldown, set 2, 100 pounds, 12 reps": what VoiceOver
    /// reads for the row.
    let summary: String
    /// What the check sends: the set logged, or un-logged once it is.
    let check: WorkoutEdit
}

/// The two steppers under the shown row: the step each moves by, and the row's values as VoiceOver reads
/// them after a step.
nonisolated struct SteppersModel: Equatable, Sendable {
    /// The row the steppers change, and its exercise's place.
    let exerciseIndex: Int
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

/// "REMAINING": the exercises outside the shown card or block that still have a set to log, in workout
/// order, earlier ones included (F10 S9, rulings Q5 and Q6), each a way to jump to it; every exercise when
/// none is shown.
nonisolated struct RemainingModel: Equatable, Sendable {
    let title: String
    let rows: [Row]

    nonisolated struct Row: Equatable, Sendable, Identifiable {
        /// The exercise's place in the workout.
        let exerciseIndex: Int
        let name: String
        /// "3 × 10": its sets without a drop set, and the reps of the first.
        let scheme: String

        var id: Int {
            exerciseIndex
        }
    }
}
