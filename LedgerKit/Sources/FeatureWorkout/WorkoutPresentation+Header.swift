import Foundation
import LedgerDesign
import LedgerDomain

nonisolated extension WorkoutPresentation {
    /// The header of a live workout.
    ///
    /// The current exercise is the one that holds the workout's cursor, read through `checkedCursor`: a
    /// cursor that names no row marks no segment, and the progress then has no value to speak. S5 passes the
    /// row the lifter selected in its place.
    static func header(_ state: WorkoutState, isBusy: Bool, locale: Locale) -> WorkoutHeaderModel {
        let current = state.checkedCursor?.exerciseIndex
        return WorkoutHeaderModel(
            minimize: WorkoutCopy.minimize,
            finish: WorkoutCopy.finish,
            isEnabled: !isBusy,
            startedAt: state.startedAt,
            elapsedLabel: WorkoutCopy.elapsedTime,
            title: state.name,
            segments: segments(of: state.exercises, current: current),
            progressLabel: WorkoutCopy.workoutProgress,
            progressValue: current.map {
                WorkoutCopy.exercise($0 + 1, of: state.exercises.count, locale: locale)
            } ?? ""
        )
    }

    /// Rule 36: one segment per exercise, as long as its set count. The exercise at `current` is the
    /// current one, whatever its sets, so the orange segment is always the exercise the words name; of the
    /// others, one whose every set is done is done, and the rest are upcoming. An exercise with no set is
    /// upcoming, and draws nothing.
    static func segments(of exercises: [WorkoutExercise], current: Int?) -> [ProgressSegment] {
        exercises.enumerated().map { index, exercise in
            let state: ProgressSegment.State = if index == current {
                .current
            } else if !exercise.sets.isEmpty, exercise.sets.allSatisfy(\.isDone) {
                .done
            } else {
                .upcoming
            }
            return ProgressSegment(length: exercise.sets.count, state: state)
        }
    }
}
