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
    ///
    /// `connection` is the live connection to the watch as last heard, nil before the first word of it, and
    /// `hasHeardTheWatch` whether the cover has heard the watch reached: only the line reads them
    /// (`connectionLine`), never `isEnabled`, so logging is never blocked on the watch.
    static func header(
        _ state: WorkoutState,
        isBusy: Bool,
        locale: Locale,
        selection: WorkoutSelection? = nil,
        connection: LiveConnectionState? = nil,
        hasHeardTheWatch: Bool = false
    ) -> WorkoutHeaderModel {
        let shown = shownExercise(of: state, selection: selection)
        // The shown exercise is the current one while it has a set to log: none is current once every set is
        // logged, or when no exercise is shown.
        let current = shown.flatMap { hasASetToLog(state.exercises[$0]) ? $0 : nil }
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
            } ?? "",
            connection: connectionLine(connection, hasHeardTheWatch: hasHeardTheWatch)
        )
    }

    /// F17 criterion 12: "Watch not connected — logging continues" while the transport is `reconnecting`, the 30 s
    /// after the watch was last reached, and in `solo` once this cover has heard any other state
    /// (`hasHeardTheWatch`): the watch took part and is still away. Connected says nothing, nor does degraded, whose
    /// other channel still reaches the watch, nor solo on a cover that never heard the watch: a lifter with no
    /// watch never reads the line (F17 S8, decision 1).
    static func connectionLine(_ connection: LiveConnectionState?, hasHeardTheWatch: Bool = false) -> String? {
        switch connection {
        case .reconnecting: WorkoutCopy.watchNotConnected
        case .solo where hasHeardTheWatch: WorkoutCopy.watchNotConnected
        default: nil
        }
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
