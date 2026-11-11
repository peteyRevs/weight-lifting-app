import Foundation
import LedgerDomain

/// A superset drawn as one block (F10 S9; spec §3.7, rules 19, 20 and 44; v1's legend). The rounds, the
/// letters and the group's rest are the Domain's (`SupersetRounds`); nothing here counts a round of its own.
nonisolated extension WorkoutPresentation {
    /// The block of more than one member that holds the exercise at `index`; nil for a solo exercise, which
    /// is drawn as its card.
    static func superset(holding index: Int, in exercises: [WorkoutExercise]) -> SupersetRounds.Block? {
        SupersetRounds.blocks(in: exercises).first {
            $0.exerciseIndices.count > 1 && $0.exerciseIndices.contains(index)
        }
    }

    /// The shown row of a block (criterion 8): the row the lifter chose while it is undone, else the engine's
    /// cursor while it is in the block and undone, else the block's first undone row in display order. Nil
    /// with every row of the block logged.
    static func shownRow(
        of block: SupersetRounds.Block,
        in state: WorkoutState,
        _ selection: WorkoutSelection?
    ) -> SupersetRounds.SetRef? {
        let open = SupersetRounds.displayOrder(block: block, exercises: state.exercises).filter {
            !state.exercises[$0.exerciseIndex].sets[$0.setIndex].isDone
        }
        let chosen = open.first { row in
            row.exerciseIndex == selection?.exerciseIndex
                && state.exercises[row.exerciseIndex].sets[row.setIndex].id == selection?.setID
        }
        let cursor = state.checkedCursor.flatMap { cursor in
            open.first { $0.exerciseIndex == cursor.exerciseIndex && $0.setIndex == cursor.setIndex }
        }
        return chosen ?? cursor ?? open.first
    }

    /// The block's model: its place among the workout's blocks, its round, its legend, the group's rest, the
    /// current member's "Last" and "Repeat", and its rows in display order.
    static func supersetBlock(
        _ block: SupersetRounds.Block,
        in state: WorkoutState,
        selection: WorkoutSelection?,
        _ context: Context,
        isBusy: Bool
    ) -> SupersetBlockModel {
        let locale = context.locale
        let blocks = SupersetRounds.blocks(in: state.exercises)
        let shown = shownRow(of: block, in: state, selection)
        let shownSet = shown.map { state.exercises[$0.exerciseIndex].sets[$0.setIndex].id }
        let groupRest = SupersetRounds.groupRest(block: block, exercises: state.exercises)
        let lastLetter = SupersetRounds.letter(forMemberAt: block.exerciseIndices.count - 1)
        return SupersetBlockModel(
            eyebrow: WorkoutCopy.supersetBlock(
                (blocks.firstIndex(of: block) ?? 0) + 1,
                of: blocks.count,
                locale: locale
            ),
            title: round(of: block, in: state, locale: locale),
            legend: legend(of: block, in: state, current: shown?.exerciseIndex, isBusy: isBusy, locale: locale),
            restLine: WorkoutCopy.restAfter(groupRest.label, letter: lastLetter, locale: locale),
            restLineSpoken: WorkoutCopy.restAfter(
                spokenRestTime(groupRest.duration, locale: locale), letter: lastLetter, locale: locale
            ),
            current: shown.map { current($0.exerciseIndex, in: state, context) },
            columns: columns(state.units),
            rows: rows(of: block, in: state, shown: shownSet, locale: locale),
            steppers: shown.flatMap { row in
                shownSet.flatMap { steppers(for: $0, of: row.exerciseIndex, in: state, locale: locale) }
            },
            addSet: WorkoutCopy.addSet
        )
    }

    /// The block's rows in display order (rule 20; criteria 10 and 11), each labelled by its member's letter.
    private static func rows(
        of block: SupersetRounds.Block,
        in state: WorkoutState,
        shown: SetID?,
        locale: Locale
    ) -> [SetRowModel] {
        let byMember = Dictionary(uniqueKeysWithValues: block.exerciseIndices.enumerated().map { position, index in
            let letter = SupersetRounds.letter(forMemberAt: position)
            let rows = setRows(
                of: state.exercises[index], at: index, active: shown, units: state.units, locale: locale, letter: letter
            )
            return (index, rows)
        })
        return SupersetRounds.displayOrder(block: block, exercises: state.exercises).compactMap { row in
            byMember[row.exerciseIndex]?[row.setIndex]
        }
    }

    /// "Round 2 of 3" (criterion 6): the round that holds the first undone row in display order, of every
    /// round, drop rounds included; with every row logged, the last.
    private static func round(of block: SupersetRounds.Block, in state: WorkoutState, locale: Locale) -> String {
        let rounds = SupersetRounds.rounds(block: block, exercises: state.exercises)
        let firstOpen = rounds.firstIndex { round in
            round.contains { !state.exercises[$0.exerciseIndex].sets[$0.setIndex].isDone }
        }
        return WorkoutCopy.round((firstOpen ?? rounds.count - 1) + 1, of: rounds.count, locale: locale)
    }

    /// One row per member (criteria 7 and 9): its letter, its name and its target without RPE, whether it
    /// holds the shown row, and its swap button while none of its sets is logged and the page answers.
    private static func legend(
        of block: SupersetRounds.Block,
        in state: WorkoutState,
        current: Int?,
        isBusy: Bool,
        locale: Locale
    ) -> [SupersetBlockModel.LegendRow] {
        block.exerciseIndices.enumerated().map { position, index in
            let exercise = state.exercises[index]
            let letter = SupersetRounds.letter(forMemberAt: position)
            let target = WorkoutCopy.legendTarget(
                sets: exercise.targetSets,
                reps: exercise.targetReps,
                load: exercise.targetLoad.formatted(in: state.units),
                units: state.units,
                locale: locale
            )
            return SupersetBlockModel.LegendRow(
                exerciseIndex: index,
                exerciseID: exercise.exerciseID,
                letter: letter,
                name: exercise.name,
                target: target,
                isCurrent: index == current,
                swap: canSwap(exercise) && !isBusy ? WorkoutCopy.swapMember(exercise.name, locale: locale) : nil,
                spoken: [letter, exercise.name, target].joined(separator: ", ")
            )
        }
    }

    /// The current member's "Last" and "Repeat" (ruling Q1), as its card would draw them.
    private static func current(
        _ index: Int,
        in state: WorkoutState,
        _ context: Context
    ) -> SupersetBlockModel.CurrentMember {
        let last = lastWorkout(of: state.exercises[index], units: state.units, calendar: context.calendar)
        return SupersetBlockModel.CurrentMember(
            exerciseIndex: index,
            lastLabel: WorkoutCopy.last,
            last: last.line,
            repeatLast: last.repeatLast
        )
    }
}
