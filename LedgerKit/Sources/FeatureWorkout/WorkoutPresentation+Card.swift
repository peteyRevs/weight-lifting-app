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
    ///
    /// In a superset (F10 S9 criterion 8) it is the member that holds the block's shown row
    /// (`shownRow(of:in:_:)`), so a chosen member with nothing left gives way to the member of the block's
    /// first undone row, and the header, the legend, the steppers and the rest panel never disagree. With
    /// every row of the block logged it is the exercise named above.
    static func shownExercise(of state: WorkoutState, selection: WorkoutSelection?) -> Int? {
        let named: Int? = if let selection, state.exercises.indices.contains(selection.exerciseIndex) {
            selection.exerciseIndex
        } else {
            state.checkedCursor.flatMap {
                currentExercise(of: state.exercises, cursor: $0.exerciseIndex) ?? $0.exerciseIndex
            }
        }
        guard let named, let block = superset(holding: named, in: state.exercises),
              let row = shownRow(of: block, in: state, selection)
        else {
            return named
        }
        return row.exerciseIndex
    }

    static func hasASetToLog(_ exercise: WorkoutExercise) -> Bool {
        exercise.sets.contains { !$0.isDone }
    }

    /// The shown row of the exercise at `index`: the row the lifter chose, else the engine's cursor when it
    /// is in this exercise, else the exercise's first row, each only while it is not logged. A logged row is
    /// never the shown row, so with every set logged there is none. A member of a superset has a shown row
    /// only while it holds its block's (F10 S9).
    static func activeSet(of index: Int, in state: WorkoutState, _ selection: WorkoutSelection?) -> SetID? {
        guard state.exercises.indices.contains(index) else {
            return nil
        }
        if let block = superset(holding: index, in: state.exercises) {
            return shownRow(of: block, in: state, selection).flatMap { row in
                row.exerciseIndex == index ? state.exercises[index].sets[row.setIndex].id : nil
            }
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

    /// The page under the header: the shown exercise's card, or its superset's block, and the exercises
    /// outside it that still have a set to log.
    static func page(
        _ state: WorkoutState,
        selection: WorkoutSelection?,
        isBusy: Bool,
        _ context: Context
    ) -> WorkoutPageModel {
        let shown = shownExercise(of: state, selection: selection)
        let block = shown.flatMap { superset(holding: $0, in: state.exercises) }
        let onScreen = block?.exerciseIndices ?? shown.map { [$0] } ?? []
        // Criterion 16, with F10 S9's rulings Q5 and Q6: every exercise outside the shown card or block that
        // can still be logged, earlier ones included, in workout order, so that no row leads to a page with
        // nothing to do; each with its sets without the drop set, as a target line counts them. With no
        // exercise shown every exercise is listed, so that each can be reached.
        let listed = state.exercises.enumerated().filter { index, exercise in
            shown == nil || !onScreen.contains(index) && hasASetToLog(exercise)
        }
        let rows = listed.map { index, exercise in
            RemainingModel.Row(
                exerciseIndex: index,
                name: exercise.name,
                scheme: WorkoutCopy.scheme(
                    sets: exercise.sets.count { $0.kind != .drop },
                    reps: exercise.sets.first?.reps.value ?? exercise.targetReps,
                    locale: context.locale
                )
            )
        }
        let content: WorkoutPageModel.Content? = if let block {
            .block(supersetBlock(block, in: state, selection: selection, context, isBusy: isBusy))
        } else {
            shown.map { .card(card(of: $0, in: state, selection: selection, context, isBusy: isBusy)) }
        }
        return WorkoutPageModel(
            content: content,
            remaining: rows.isEmpty ? nil : RemainingModel(title: WorkoutCopy.remaining, rows: rows),
            isEnabled: !isBusy
        )
    }

    /// The card of the exercise at `index`, which the caller knows to be in the workout. A member of a
    /// superset of more than one member is drawn in its block instead (`supersetBlock`).
    static func card(
        of index: Int,
        in state: WorkoutState,
        selection: WorkoutSelection?,
        _ context: Context,
        isBusy: Bool = false
    ) -> ExerciseCardModel {
        let exercise = state.exercises[index]
        let units = state.units
        let active = activeSet(of: index, in: state, selection)
        let rows = setRows(of: exercise, at: index, active: active, units: units, locale: context.locale)
        let last = exercise.lastPerformance
        return ExerciseCardModel(
            exerciseIndex: index,
            exerciseID: exercise.exerciseID,
            eyebrow: WorkoutCopy.exercise(index + 1, of: state.exercises.count, locale: context.locale),
            title: exercise.name,
            swap: canSwap(exercise) && !isBusy ? WorkoutCopy.swapExercise : nil,
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
            steppers: active.flatMap { steppers(for: $0, of: index, in: state, locale: context.locale) },
            addSet: WorkoutCopy.addSet
        )
    }

    /// The steppers under the row `setID` of the exercise at `index`: its exercise's step in the workout's
    /// unit, and the row's values as VoiceOver reads them. Nil for a row the exercise does not hold.
    static func steppers(for setID: SetID, of index: Int, in state: WorkoutState, locale: Locale) -> SteppersModel? {
        let exercise = state.exercises[index]
        let units = state.units
        return exercise.sets.first { $0.id == setID }.map { set in
            SteppersModel(
                exerciseIndex: index,
                setID: set.id,
                weightStep: WorkoutCopy.weightStep(exercise.step.formatted(in: units), units: units, locale: locale),
                repStep: WorkoutCopy.repStep,
                weight: WorkoutCopy.spokenWeight(set.weight.formatted(in: units), units: units, locale: locale),
                reps: WorkoutCopy.spokenReps(set.reps.value, locale: locale)
            )
        }
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
    ///
    /// A superset's member passes its `letter` (F10 S9 criteria 10 and 11): the label is "A1" or "AD", the
    /// row is read with the member's name first ("Lat Pulldown, set 2, …"), and the check names the label
    /// ("Log set A2").
    static func setRows(
        of exercise: WorkoutExercise,
        at index: Int,
        active: SetID?,
        units: Units,
        locale: Locale,
        letter: String? = nil
    ) -> [SetRowModel] {
        var number = 0
        return exercise.sets.map { set in
            let isDrop = set.kind == .drop
            number += isDrop ? 0 : 1
            let weight = set.weight.formatted(in: units)
            let words = rowWords(
                number: isDrop ? nil : number,
                isDone: set.isDone,
                member: letter.map { ($0, exercise.name) },
                locale: locale
            )
            let spoken = [
                words.spoken,
                WorkoutCopy.spokenWeight(weight, units: units, locale: locale),
                WorkoutCopy.spokenReps(set.reps.value, locale: locale)
            ]
            return SetRowModel(
                id: set.id,
                exerciseIndex: index,
                label: words.label,
                weight: weight,
                reps: String(set.reps.value),
                state: set.isDone ? .done : set.id == active ? .active : .pending,
                checkLabel: words.check,
                summary: spoken.joined(separator: ", "),
                check: set.isDone
                    ? .unlog(exerciseIndex: index, setID: set.id)
                    : .log(exerciseIndex: index, setID: set.id)
            )
        }
    }

    /// A row's label, its spoken name and what its check will do. Solo: "2", "Set 2", "Log set 2" or "Undo
    /// set 2"; a drop set, which has no number: "D", "Drop set", "Log drop set" or "Undo drop set". A
    /// superset's member (F10 S9): "A2", "Lat Pulldown, set 2", "Log set A2"; "AD", "Lat Pulldown, drop set",
    /// "Undo set AD".
    private static func rowWords(
        number: Int?,
        isDone: Bool,
        member: (letter: String, name: String)?,
        locale: Locale
    ) -> RowWords {
        let label = number.map(String.init) ?? WorkoutCopy.dropSetLabel
        if let member {
            let named = member.letter + label
            let spoken = number.map { WorkoutCopy.spokenMemberSet(member.name, $0, locale: locale) }
                ?? WorkoutCopy.spokenMemberDropSet(member.name, locale: locale)
            return RowWords(
                label: named,
                spoken: spoken,
                check: isDone ? WorkoutCopy.undoRow(named, locale: locale) : WorkoutCopy.logRow(named, locale: locale)
            )
        }
        let check = switch (number, isDone) {
        case let (number?, false): WorkoutCopy.logSet(number, locale: locale)
        case let (number?, true): WorkoutCopy.undoSet(number, locale: locale)
        case (nil, false): WorkoutCopy.logDropSet
        case (nil, true): WorkoutCopy.undoDropSet
        }
        let spoken = number.map { WorkoutCopy.spokenSet($0, locale: locale) } ?? WorkoutCopy.spokenDropSet
        return RowWords(label: label, spoken: spoken, check: check)
    }

    /// A row's words: its label, its spoken name and what its check will do.
    private struct RowWords {
        let label: String
        let spoken: String
        let check: String
    }
}
