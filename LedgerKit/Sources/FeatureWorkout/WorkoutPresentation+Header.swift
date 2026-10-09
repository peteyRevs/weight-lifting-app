import Foundation
import LedgerDesign
import LedgerDomain

nonisolated extension WorkoutPresentation {
    /// The header of a live workout.
    ///
    /// Its current segment and its words name the exercise on screen (`shownExercise`): the one the lifter
    /// chose, otherwise the cursor's while it has a set to log, otherwise the first that has one, so the
    /// orange bar, "Exercise 2 of 5" and the card under them never disagree. The cursor is read through
    /// `checkedCursor`: one that names no row marks no segment, and the progress then has no value to speak.
    /// With every set logged the words name the exercise the cursor rests on, and no segment is current.
    static func header(
        _ state: WorkoutState,
        isBusy: Bool,
        locale: Locale,
        selection: WorkoutSelection? = nil
    ) -> WorkoutHeaderModel {
        let shown = shownExercise(of: state, selection: selection)
        let cursor = state.checkedCursor?.exerciseIndex
        // Without a choice of the lifter's the current segment is S4's: none once every set is logged.
        let chosen = selection.map(\.exerciseIndex).flatMap { state.exercises.indices.contains($0) ? $0 : nil }
        let current = chosen ?? currentExercise(of: state.exercises, cursor: cursor)
        return WorkoutHeaderModel(
            minimize: WorkoutCopy.minimize,
            finish: WorkoutCopy.finish,
            isEnabled: !isBusy,
            startedAt: state.startedAt,
            elapsedLabel: WorkoutCopy.elapsedTime,
            title: state.name,
            segments: segments(of: state.exercises, current: current),
            progressLabel: WorkoutCopy.workoutProgress,
            progressValue: shown.map {
                WorkoutCopy.exercise($0 + 1, of: state.exercises.count, locale: locale)
            } ?? ""
        )
    }

    /// Which exercise is the current one (F10 S4 criterion 19): the cursor's while it still has a set to log,
    /// otherwise the first that has one. The engine leaves its cursor on a finished exercise when the row
    /// logged was not the cursor's own, and the workout is not over then. Nil when every set is logged, and
    /// when the cursor names no row.
    static func currentExercise(of exercises: [WorkoutExercise], cursor: Int?) -> Int? {
        guard let cursor, exercises.indices.contains(cursor) else {
            return nil
        }
        let hasASetToLog = { (exercise: WorkoutExercise) in exercise.sets.contains { !$0.isDone } }
        return hasASetToLog(exercises[cursor]) ? cursor : exercises.firstIndex(where: hasASetToLog)
    }

    /// Rule 36: one segment per exercise, as long as its set count. An exercise whose every set is done is
    /// done, also when the cursor rests on it, so a workout with every set logged has no current segment
    /// (F10 S4 criterion 13). Of the others, the one at `current` is current and the rest are upcoming. An
    /// exercise with no set is never done, and draws nothing.
    static func segments(of exercises: [WorkoutExercise], current: Int?) -> [ProgressSegment] {
        exercises.enumerated().map { index, exercise in
            let state: ProgressSegment.State = if !exercise.sets.isEmpty, exercise.sets.allSatisfy(\.isDone) {
                .done
            } else if index == current {
                .current
            } else {
                .upcoming
            }
            return ProgressSegment(length: exercise.sets.count, state: state)
        }
    }
}
