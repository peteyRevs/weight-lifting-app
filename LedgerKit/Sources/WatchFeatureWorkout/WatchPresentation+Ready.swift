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
    /// One per set of the exercise, true when it is logged, and what VoiceOver reads for them: "2 of 5 sets logged".
    let dots: [Bool]
    let dotsSummary: String
    /// "142 BPM", or "— BPM".
    let heartRate: WatchHeartRateModel
    /// "Allow Health in iPhone Settings" while Health is denied, until the first set logged with it on screen
    /// (`WatchWorkoutStore.hasAskedForHealth`).
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
        let done = exercise.sets.count(where: \.isDone)
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
            dotsSummary: WatchWorkoutCopy.setsLogged(
                done: IntegerFormatStyle<Int>(locale: input.locale).format(done), of: exercise.sets.count,
                locale: input.locale
            ),
            heartRate: heartRateLine(input.heartRate, input.health, locale: input.locale),
            healthLine: input.health == .denied && input.offersHealthLine ? WatchWorkoutCopy.allowHealth : nil,
            connection: connectionLine(input.connection, hasHeardPhone: input.hasHeardPhone)
        )
    }
}

/// The heart-rate line (spec §4.3): the number, or "—" while there is none to show, then "BPM"; and what VoiceOver
/// reads, "Heart rate, 142 beats per minute".
nonisolated struct WatchHeartRateModel: Equatable, Sendable {
    let value: String
    let unit: String
    let label: String
    let spokenValue: String
}

/// The crown's weight on the set screen (F18 criteria 4, 14): the number as it turns, in the workout's unit, what
/// VoiceOver reads ("Weight, 190 pounds"), and the crown's binding: its position, one detent per `step`, from 0
/// through `upperBound`.
nonisolated struct CrownDial: Equatable, Sendable {
    let weight: String
    let unit: String
    let label: String
    let spokenWeight: String
    let value: Double
    let step: Double
    let upperBound: Double
}

nonisolated extension WatchPresentation {
    /// The heart-rate line of `sample` while Health is `health` (spec §9: "— BPM" without one, or when denied).
    static func heartRateLine(
        _ sample: HeartRateSample?,
        _ health: HealthAuthorization,
        locale: Locale
    ) -> WatchHeartRateModel {
        let bpm = health == .denied ? nil : sample?.bpm
        return WatchHeartRateModel(
            value: heartRate(sample, health),
            unit: WatchWorkoutCopy.bpm,
            label: WatchWorkoutCopy.heartRateLabel,
            spokenValue: bpm.map { WatchWorkoutCopy.spokenHeartRate($0, locale: locale) }
                ?? WatchWorkoutCopy.noHeartRateSpoken
        )
    }

    /// The crown's top, in its unit: 2,000 lb, 1,000 kg (F18 risks: past any lift, and no clamp at the start).
    static func crownTop(_ units: Units) -> Double {
        units == .lb ? 2000 : 1000
    }

    /// The crown's weight as `crown` stands: the number it shows, which moves before anything is sent. Nil with no
    /// set to change.
    static func crownDial(_ crown: CrownWeightModel, locale: Locale) -> CrownDial? {
        guard let reading = crown.reading, let weight = crown.weight else {
            return nil
        }
        return CrownDial(
            weight: weight.formatted(in: reading.units),
            unit: WatchWorkoutCopy.unit(reading.units),
            label: WatchWorkoutCopy.weightLabel,
            spokenWeight: weight.spoken(in: reading.units, locale: locale.forCountedText),
            value: crown.value,
            step: CrownWeightModel.number(reading.step, in: reading.units),
            upperBound: crownTop(reading.units)
        )
    }
}
