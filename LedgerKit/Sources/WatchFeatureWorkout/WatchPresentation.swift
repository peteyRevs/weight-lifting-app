import Foundation
import LedgerDomain

/// Pure functions from what the watch's store holds to what its screens draw (M1 store convention; spec §4.3, §5.1).
/// Every string is resolved here, through `WatchWorkoutCopy`; numbers and units are printed as `LedgerDomain` prints
/// them. No function reads a clock, a calendar, a locale or a time zone of its own: `now` and the rest are handed in.
/// The screens' derivations are in the extension files, one per screen.
nonisolated enum WatchPresentation {
    /// What joins the fragments of a line: "A · SET 2 OF 3".
    static let separator = " · "

    /// The row the watch shows, in `exercises[exercise]`; `set` is nil when that exercise has no set left to log.
    struct ActiveRow: Equatable {
        let exercise: Int
        let set: Int?
    }

    /// The row the set screen shows and "Done set" logs: the phone's shown row with nothing chosen on the phone
    /// (`WorkoutPresentation.shownExercise` and `activeSet`, FeatureWorkout), since a row picked on the watch moves
    /// the engine's cursor. The cursor's exercise while it has a set to log, otherwise the first that has one; in
    /// it, the cursor's row while it is undone, otherwise the first undone row, in round order in a superset, where
    /// the row may be another member's. Nil without a cursor that names a row (an empty workout).
    static func activeRow(of state: WorkoutState) -> ActiveRow? {
        guard let cursor = state.checkedCursor else {
            return nil
        }
        let exercises = state.exercises
        let isOpen = { (row: SupersetRounds.SetRef) in !exercises[row.exerciseIndex].sets[row.setIndex].isDone }
        let hasOpen = { (index: Int) in exercises[index].sets.contains { !$0.isDone } }
        let shown = hasOpen(cursor.exerciseIndex)
            ? cursor.exerciseIndex : exercises.indices.first(where: hasOpen) ?? cursor.exerciseIndex
        let block = SupersetRounds.blocks(in: exercises).first { $0.exerciseIndices.contains(shown) }
        let rows = if let block, block.exerciseIndices.count > 1 {
            SupersetRounds.displayOrder(block: block, exercises: exercises)
        } else {
            exercises[shown].sets.indices.map { SupersetRounds.SetRef(exerciseIndex: shown, setIndex: $0) }
        }
        let atCursor = SupersetRounds.SetRef(exerciseIndex: cursor.exerciseIndex, setIndex: cursor.setIndex)
        let row = rows.contains(atCursor) && isOpen(atCursor) ? atCursor : rows.first(where: isOpen)
        return ActiveRow(exercise: row?.exerciseIndex ?? shown, set: row?.setIndex)
    }

    /// The superset letter of the exercise at `index` ("A", "B"…); nil for a solo exercise.
    static func letter(of index: Int, in exercises: [WorkoutExercise]) -> String? {
        SupersetRounds.blocks(in: exercises)
            .first { $0.exerciseIndices.count > 1 && $0.exerciseIndices.contains(index) }
            .flatMap { $0.exerciseIndices.firstIndex(of: index) }
            .map(SupersetRounds.letter(forMemberAt:))
    }

    /// The workout's time, "m:ss" (rule 24): from its start to `now`, frozen at its end once it is over.
    static func elapsed(_ state: WorkoutState, at now: Date) -> String {
        ClockText.elapsed(state.elapsed(at: now))
    }

    /// The heart rate's number, or "—" while there is no sample to show or Health is denied (spec §9).
    static func heartRate(_ sample: HeartRateSample?, _ health: HealthAuthorization) -> String {
        guard health != .denied, let sample else {
            return WatchWorkoutCopy.noHeartRate
        }
        return String(sample.bpm)
    }

    /// F17 criterion 12, the watch's half: "iPhone not connected — logging continues" while the iPhone counts as
    /// away by the rule the phone's line reads too (`LiveConnectionState.isPeerAway`): reconnecting, or solo once
    /// the watch has heard the iPhone. Nothing is disabled while it shows.
    static func connectionLine(_ connection: LiveConnectionState?, hasHeardPhone: Bool) -> String? {
        LiveConnectionState.isPeerAway(connection, hasHeardThePeer: hasHeardPhone)
            ? WatchWorkoutCopy.iPhoneNotConnected : nil
    }
}

/// Everything the live screens read beside the workout: the latest heart-rate sample, Health's sharing status, the
/// live connection as last heard (nil before the first word of it), whether the watch has heard the iPhone reached,
/// and the locale the words are written in.
nonisolated struct WatchLiveInput: Sendable {
    var heartRate: HeartRateSample?
    var health: HealthAuthorization
    var connection: LiveConnectionState?
    var hasHeardPhone: Bool
    var locale: Locale
}
