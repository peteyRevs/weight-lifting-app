import Foundation
import LedgerDesign
import LedgerDomain

nonisolated extension WorkoutPresentation {
    /// What the page needs beside the workout: the lifter's language for numbers that are counted, and the
    /// calendar whose time zone decides the day of "Last". Both are injected; no function here reads one of
    /// its own.
    struct Context: Sendable {
        let locale: Locale
        let calendar: Calendar
    }

    /// The exercise on screen: the one the lifter chose while it is in the workout, otherwise the header's
    /// current exercise (the cursor's while it has a set to log, else the first that has one), and with
    /// every set logged the one the cursor rests on. Nil when the cursor names no row and nothing was
    /// chosen, and for a workout with no exercise.
    static func shownExercise(of state: WorkoutState, selection: WorkoutSelection?) -> Int? {
        if let selection, state.exercises.indices.contains(selection.exerciseIndex) {
            return selection.exerciseIndex
        }
        let cursor = state.checkedCursor?.exerciseIndex
        return currentExercise(of: state.exercises, cursor: cursor) ?? cursor
    }

    /// The shown row of the exercise at `index`: the row the lifter chose, else the engine's cursor when it
    /// is in this exercise, else the exercise's first row, each only while it is not logged. A logged row is
    /// never the shown row, so with every set logged there is none.
    static func activeSet(of index: Int, in state: WorkoutState, _ selection: WorkoutSelection?) -> SetID? {
        guard state.exercises.indices.contains(index) else {
            return nil
        }
        let open = state.exercises[index].sets.filter { !$0.isDone }.map(\.id)
        if let chosen = selection?.setID, selection?.exerciseIndex == index, open.contains(chosen) {
            return chosen
        }
        if let cursor = state.checkedCursor, cursor.exerciseIndex == index {
            let atCursor = state.exercises[index].sets[cursor.setIndex].id
            if open.contains(atCursor) {
                return atCursor
            }
        }
        return open.first
    }

    /// The page under the header: the shown exercise's card, and the exercises after it.
    static func page(
        _ state: WorkoutState,
        selection: WorkoutSelection?,
        isBusy: Bool,
        _ context: Context
    ) -> WorkoutPageModel {
        let shown = shownExercise(of: state, selection: selection)
        let later = state.exercises.enumerated().filter { $0.offset > shown ?? -1 }
        let rows = later.map { index, exercise in
            RemainingModel.Row(
                exerciseIndex: index,
                name: exercise.name,
                scheme: WorkoutCopy.scheme(
                    sets: exercise.sets.count,
                    reps: exercise.sets.first?.reps.value ?? exercise.targetReps,
                    locale: context.locale
                )
            )
        }
        return WorkoutPageModel(
            card: shown.map { card(of: $0, in: state, selection: selection, context) },
            remaining: rows.isEmpty ? nil : RemainingModel(title: WorkoutCopy.remaining, rows: rows),
            isEnabled: !isBusy
        )
    }

    /// The card of the exercise at `index`, which the caller knows to be in the workout.
    ///
    /// A member of a superset is drawn as any other exercise until S9 draws the block: the engine still
    /// runs the rounds, so logging one member's set moves the cursor, and the card, to the next member.
    static func card(
        of index: Int,
        in state: WorkoutState,
        selection: WorkoutSelection?,
        _ context: Context
    ) -> ExerciseCardModel {
        let exercise = state.exercises[index]
        let units = state.units
        let active = activeSet(of: index, in: state, selection)
        let rows = setRows(of: exercise, at: index, active: active, units: units, locale: context.locale)
        let last = exercise.lastPerformance
        return ExerciseCardModel(
            exerciseIndex: index,
            eyebrow: WorkoutCopy.exercise(index + 1, of: state.exercises.count, locale: context.locale),
            title: exercise.name,
            targetLabel: WorkoutCopy.target,
            target: target(of: exercise, units: units, locale: context.locale),
            lastLabel: WorkoutCopy.last,
            last: last?.line(units: units, calendar: context.calendar) ?? WorkoutCopy.noHistoryYet,
            repeatLast: last == nil ? nil : WorkoutCopy.repeatLast,
            columns: ExerciseCardModel.Columns(
                number: WorkoutCopy.numberColumn,
                weight: WorkoutCopy.unit(units),
                reps: WorkoutCopy.repsColumn
            ),
            rows: rows,
            steppers: exercise.sets.first { $0.id == active }.map { set in
                SteppersModel(
                    setID: set.id,
                    weightStep: WorkoutCopy.weightStep(
                        exercise.step.formatted(in: units), units: units, locale: context.locale
                    ),
                    repStep: WorkoutCopy.repStep,
                    weight: WorkoutCopy.spokenWeight(
                        set.weight.formatted(in: units), units: units, locale: context.locale
                    ),
                    reps: WorkoutCopy.spokenReps(set.reps.value, locale: context.locale)
                )
            },
            addSet: WorkoutCopy.addSet
        )
    }

    /// "5 × 5 @ 185 lb · RPE 8": what the program prescribed, in the workout's unit.
    private static func target(of exercise: WorkoutExercise, units: Units, locale: Locale) -> String {
        let load = exercise.targetLoad.formatted(in: units)
        return switch units {
        case .lb:
            WorkoutCopy.targetPounds(
                sets: exercise.targetSets, reps: exercise.targetReps, load: load, rpe: exercise.rpe.label,
                locale: locale
            )
        case .kg:
            WorkoutCopy.targetKilograms(
                sets: exercise.targetSets, reps: exercise.targetReps, load: load, rpe: exercise.rpe.label,
                locale: locale
            )
        }
    }

    /// One row per set, in the exercise's order. The rows that are not drop sets count "1", "2", …; a drop
    /// set is "D" (spec §3.7), so a set added after a drop set takes the next number. The label and the
    /// reps are written in plain digits, as the Domain writes the weight beside them.
    private static func setRows(
        of exercise: WorkoutExercise,
        at index: Int,
        active: SetID?,
        units: Units,
        locale: Locale
    ) -> [SetRowModel] {
        var number = 0
        return exercise.sets.map { set in
            let isDrop = set.kind == .drop
            number += isDrop ? 0 : 1
            let weight = set.weight.formatted(in: units)
            let spoken = [
                isDrop ? WorkoutCopy.spokenDropSet : WorkoutCopy.spokenSet(number, locale: locale),
                WorkoutCopy.spokenWeight(weight, units: units, locale: locale),
                WorkoutCopy.spokenReps(set.reps.value, locale: locale)
            ]
            return SetRowModel(
                id: set.id,
                label: isDrop ? WorkoutCopy.dropSetLabel : String(number),
                weight: weight,
                reps: String(set.reps.value),
                state: set.isDone ? .done : set.id == active ? .active : .pending,
                checkLabel: checkLabel(number: isDrop ? nil : number, isDone: set.isDone, locale: locale),
                summary: spoken.joined(separator: ", "),
                check: set.isDone
                    ? .unlog(exerciseIndex: index, setID: set.id)
                    : .log(exerciseIndex: index, setID: set.id)
            )
        }
    }

    /// What the check will do: "Log set 2" or "Undo set 2"; for a drop set, which has no number, "Log drop
    /// set" or "Undo drop set".
    private static func checkLabel(number: Int?, isDone: Bool, locale: Locale) -> String {
        switch (number, isDone) {
        case let (number?, false): WorkoutCopy.logSet(number, locale: locale)
        case let (number?, true): WorkoutCopy.undoSet(number, locale: locale)
        case (nil, false): WorkoutCopy.logDropSet
        case (nil, true): WorkoutCopy.undoDropSet
        }
    }
}
