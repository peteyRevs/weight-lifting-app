import Foundation
import LedgerDomain

/// What the set screen draws (spec §4.3 "Watch — set ready", §5.1).
nonisolated struct WatchReadyModel: Equatable, Sendable {
    /// "SET 1 OF 5", "A · SET 2 OF 3" in a superset.
    let setLabel: String
    /// "m:ss" since the start; the screen redraws it from `startedAt`.
    let elapsed: String
    let startedAt: Date
    /// The exercise's name, as swapped; a tap opens the session list.
    let exerciseName: String
    /// The shown row's weight, "185", in the workout's unit, and the same number for the crown to start from.
    let weight: String
    let weightValue: Decimal
    /// One crown detent, in the same unit: the exercise's step.
    let step: Decimal
    /// "LB" / "KG".
    let unit: String
    /// "× 5", and the number the reps buttons change.
    let reps: String
    let repsValue: Int
    /// "RPE 8".
    let target: String
    /// One per set of the exercise, true when it is logged.
    let dots: [Bool]
    /// "142", or "—".
    let heartRate: String
    /// "Allow Health in iPhone Settings" while Health is denied; the store shows it once.
    let healthLine: String?
    /// The connection line under the set label (F17 criterion 12), or nil.
    let connection: String?
}

nonisolated extension WatchPresentation {
    /// The set screen of `state` at `now`: the active row (`activeRow(of:)`) of its exercise. With every set of
    /// that exercise logged, its last row stands in, so the screen still names a set. Nil for an empty workout.
    ///
    /// Weights are in the workout's own unit, as the phone's card prints them (`WorkoutState.units`, the settings'
    /// unit when the workout was built); the step is the exercise's, or its equipment's in that unit
    /// (`SetEditing.step`).
    static func ready(_ state: WorkoutState, at now: Date, _ input: WatchLiveInput) -> WatchReadyModel? {
        guard let active = activeRow(of: state) else {
            return nil
        }
        let exercise = state.exercises[active.exercise]
        guard let shown = active.set ?? exercise.sets.indices.last else {
            return nil
        }
        let set = exercise.sets[shown]
        let units = state.units
        let label = WatchWorkoutCopy.set(shown + 1, of: exercise.sets.count, locale: input.locale)
        return WatchReadyModel(
            setLabel: letter(of: active.exercise, in: state.exercises).map { $0 + separator + label } ?? label,
            elapsed: elapsed(state, at: now),
            startedAt: state.startedAt,
            exerciseName: exercise.name,
            weight: set.weight.formatted(in: units),
            weightValue: set.weight.shownValue(in: units),
            step: SetEditing.step(of: exercise, loggedIn: units, readIn: units).value(in: units),
            unit: WatchWorkoutCopy.unit(units),
            reps: WatchWorkoutCopy.reps(set.reps.value, locale: input.locale),
            repsValue: set.reps.value,
            target: WatchWorkoutCopy.rpe(exercise.rpe.label, locale: input.locale),
            dots: exercise.sets.map(\.isDone),
            heartRate: heartRate(input.heartRate, input.health),
            healthLine: input.health == .denied ? WatchWorkoutCopy.allowHealth : nil,
            connection: connectionLine(input.connection, hasHeardPhone: input.hasHeardPhone)
        )
    }
}
