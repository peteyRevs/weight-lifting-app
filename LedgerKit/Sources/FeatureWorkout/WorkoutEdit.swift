import Foundation
import LedgerDesign
import LedgerDomain

/// One tap on the workout's page that changes the workout (F10 S5). A row is named by its exercise's place
/// and its set's id, as the engine's events name it, so a tap means the same row however many taps are
/// waiting before it. The views send these inside `WorkoutAction.edit`; `WorkoutStore` queues them and its
/// pump applies them one at a time, in the order they were made.
nonisolated enum WorkoutEdit: Equatable, Sendable {
    /// A tap on a row's body: it becomes the shown row.
    case select(exerciseIndex: Int, setID: SetID)
    /// The check of a row that was drawn not done. A second tap that was made before the first was drawn
    /// finds the row done and does nothing, so a double tap logs once.
    case log(exerciseIndex: Int, setID: SetID)
    /// The check of a row that was drawn done.
    case unlog(exerciseIndex: Int, setID: SetID)
    /// "−" or "+" on the weight, by the exercise's step.
    case stepWeight(exerciseIndex: Int, setID: SetID, SetRowSteppers.Direction)
    /// "−" or "+" on the reps, by one.
    case stepReps(exerciseIndex: Int, setID: SetID, SetRowSteppers.Direction)
    /// "Repeat": every set of the exercise takes the last workout's weight and reps.
    case repeatLast(exerciseIndex: Int)
    /// "+ Add set".
    case addSet(exerciseIndex: Int)
    /// A row of "REMAINING": that exercise becomes the shown one.
    case jump(exerciseIndex: Int)
}

/// The row the lifter chose, where it is not the engine's cursor: the engine moves its cursor only onto a
/// row that is not done (rule 11), and the cover can also show an exercise whose every set is logged. It
/// belongs to one presentation of the cover; a set that is logged hands the choice back to the engine's
/// cursor (rule 20).
nonisolated struct WorkoutSelection: Equatable, Sendable {
    let exerciseIndex: Int
    /// Nil when the exercise was jumped to and had no set left to log.
    let setID: SetID?
}

/// What an edit comes to on the workout as it stands: the events to apply, in order, and the selection
/// afterwards. A pure function of its inputs: the time of a logged set and the id of an added one are
/// handed in.
nonisolated struct WorkoutEditPlan: Equatable, Sendable {
    var events: [WorkoutEvent] = []
    var selection: WorkoutSelection?

    /// The plan of `edit`. An edit that names a row or an exercise the workout does not hold, or a row in
    /// the wrong state for it (a logged row to log, a row that is not logged to un-log or to step), comes
    /// to nothing: no event, and the selection as it was.
    ///
    /// The steps and their floors are the Domain's: a weight moves by the exercise's own step
    /// (`Weight.advanced(bySteps:of:)`) and the engine holds it at zero; reps move by one through
    /// `Reps(clamping:)`. A step that would change nothing sends nothing.
    static func make(
        _ edit: WorkoutEdit,
        in state: WorkoutState,
        selection: WorkoutSelection?,
        now: Date,
        newSetID: () -> SetID
    ) -> WorkoutEditPlan {
        var plan = WorkoutEditPlan(selection: selection)
        switch edit {
        case let .select(exerciseIndex, setID):
            plan.select(setID, of: exerciseIndex, in: state)
        case let .log(exerciseIndex, setID):
            plan.log(setID, of: exerciseIndex, in: state, at: now)
        case let .unlog(exerciseIndex, setID):
            plan.unlog(setID, of: exerciseIndex, in: state)
        case let .stepWeight(exerciseIndex, setID, direction):
            plan.step(setID, of: exerciseIndex, in: state) { row in
                let target = max(row.set.weight.advanced(bySteps: direction.steps, of: row.exercise.step), .zero)
                return target == row.set.weight ? nil : (target, nil)
            }
        case let .stepReps(exerciseIndex, setID, direction):
            plan.step(setID, of: exerciseIndex, in: state) { row in
                let target = Reps(clamping: row.set.reps.value + direction.steps)
                return target == row.set.reps ? nil : (nil, target)
            }
        case let .repeatLast(exerciseIndex):
            plan.repeatLast(of: exerciseIndex, in: state)
        case let .addSet(exerciseIndex):
            plan.addSet(to: exerciseIndex, in: state, id: newSetID)
        case let .jump(exerciseIndex):
            plan.jump(to: exerciseIndex, in: state)
        }
        return plan
    }

    /// Rule 18: the set is logged as its row reads, at `now`. The engine then moves its cursor (rule 20),
    /// and the selection is handed back to it.
    private mutating func log(_ setID: SetID, of exerciseIndex: Int, in state: WorkoutState, at now: Date) {
        guard let row = Row(setID, of: exerciseIndex, in: state), !row.set.isDone else {
            return
        }
        events.append(.setLogged(
            exerciseIndex: exerciseIndex,
            setID: setID,
            weight: row.set.weight,
            reps: row.set.reps,
            doneAt: now
        ))
        selection = nil
    }

    /// Rule 22: un-logging moves nothing, the selection included.
    private mutating func unlog(_ setID: SetID, of exerciseIndex: Int, in state: WorkoutState) {
        if let row = Row(setID, of: exerciseIndex, in: state), row.set.isDone {
            events.append(.setUnlogged(exerciseIndex: exerciseIndex, setID: setID))
        }
    }

    /// Rule 25: every set takes the last workout's weight and reps. Without a last workout there is no
    /// "Repeat" to tap.
    private mutating func repeatLast(of exerciseIndex: Int, in state: WorkoutState) {
        guard state.exercises.indices.contains(exerciseIndex),
              let last = state.exercises[exerciseIndex].lastPerformance
        else {
            return
        }
        events.append(.allSetsRepeated(
            exerciseIndex: exerciseIndex,
            weight: last.load,
            reps: Reps(clamping: last.reps)
        ))
    }

    /// Rule 26: a copy of the last row's weight and reps; the engine adds it as a row that is not a drop set.
    private mutating func addSet(to exerciseIndex: Int, in state: WorkoutState, id: () -> SetID) {
        guard state.exercises.indices.contains(exerciseIndex) else {
            return
        }
        let last = state.exercises[exerciseIndex].sets.last
        events.append(.setAdded(exerciseIndex: exerciseIndex, set: LoggedSet(
            id: id(),
            weight: last?.weight ?? .zero,
            reps: last?.reps ?? Self.repsOfAFirstSet,
            kind: .added
        )))
    }

    /// Spec §3.7: "+ Add set" on an exercise with no row adds 0 × 8.
    static let repsOfAFirstSet = Reps(clamping: 8)

    /// A row that is not logged becomes the shown row, here and, through `exerciseSelected`, for the
    /// engine's cursor. A logged row cannot be the shown row (it has no steppers and its check un-logs it).
    private mutating func select(_ setID: SetID, of exerciseIndex: Int, in state: WorkoutState) {
        guard let row = Row(setID, of: exerciseIndex, in: state), !row.set.isDone else {
            return
        }
        events.append(.exerciseSelected(exerciseIndex: exerciseIndex, setIndex: row.setIndex))
        selection = WorkoutSelection(exerciseIndex: exerciseIndex, setID: setID)
    }

    /// Rule 28: a stepper first selects its row, when it is not the shown one, then changes that set alone.
    private mutating func step(
        _ setID: SetID,
        of exerciseIndex: Int,
        in state: WorkoutState,
        target: (Row) -> (weight: Weight?, reps: Reps?)?
    ) {
        guard let row = Row(setID, of: exerciseIndex, in: state), !row.set.isDone else {
            return
        }
        let shown = WorkoutPresentation.shownExercise(of: state, selection: selection)
        if shown != exerciseIndex || WorkoutPresentation.activeSet(of: exerciseIndex, in: state, selection) != setID {
            select(setID, of: exerciseIndex, in: state)
        }
        if let change = target(row) {
            events.append(.setTargetChanged(
                exerciseIndex: exerciseIndex,
                setID: setID,
                weight: change.weight,
                reps: change.reps
            ))
        }
    }

    /// The exercise becomes the shown one, at its first set that is not logged; with none left, it is shown
    /// with no row selected, and the engine's cursor stays where it is.
    private mutating func jump(to exerciseIndex: Int, in state: WorkoutState) {
        guard state.exercises.indices.contains(exerciseIndex) else {
            return
        }
        let sets = state.exercises[exerciseIndex].sets
        guard let setIndex = sets.firstIndex(where: { !$0.isDone }) else {
            selection = WorkoutSelection(exerciseIndex: exerciseIndex, setID: nil)
            return
        }
        events.append(.exerciseSelected(exerciseIndex: exerciseIndex, setIndex: setIndex))
        selection = WorkoutSelection(exerciseIndex: exerciseIndex, setID: sets[setIndex].id)
    }

    /// A set the workout holds, with its exercise and its place in it.
    private struct Row {
        let exercise: WorkoutExercise
        let setIndex: Int
        let set: LoggedSet

        init?(_ setID: SetID, of exerciseIndex: Int, in state: WorkoutState) {
            guard state.exercises.indices.contains(exerciseIndex),
                  let index = state.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID })
            else {
                return nil
            }
            exercise = state.exercises[exerciseIndex]
            setIndex = index
            set = exercise.sets[index]
        }
    }
}

private nonisolated extension SetRowSteppers.Direction {
    /// One step down or one step up.
    var steps: Int {
        switch self {
        case .decrement: -1
        case .increment: 1
        }
    }
}
