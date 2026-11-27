import Foundation
import LedgerDomain

/// What the rest screen draws (spec §4.3 "Watch — rest timer", §4.5 as F18 resolves it).
nonisolated struct WatchRestModel: Equatable, Sendable {
    /// "REST" while the countdown runs, "GO" in the moment after it ends (`isOver`).
    let title: String
    let isOver: Bool
    /// "m:ss" left, rounded up as a countdown is; the screen counts down to `endsAt` by itself.
    let clock: String
    let endsAt: Date
    /// The rest itself: the screen reads the ring's share and the spoken time from it as time goes by.
    let timer: RestTimer
    /// The ring's `stroke-dashoffset` on its 553 track: 0 at the start of the rest (full), 553 at its end (empty).
    let ringOffset: Double
    /// "142", or "—", and what VoiceOver reads for it: "Heart rate, 142 beats per minute".
    let heartRate: String
    let heartRateLine: WatchHeartRateModel
    /// "Next: 185 lb × 5", or "Next exercise" when no set is left.
    let next: String
    let connection: String?
    /// The locale the spoken time is written in.
    let locale: Locale

    /// What VoiceOver reads for the ring at `now`: "Rest, 42 seconds remaining", or "Rest over".
    func ringSummary(at now: Date) -> String {
        let left = timer.remaining(at: now)
        guard left > .zero else {
            return WatchWorkoutCopy.restOver
        }
        let time = Duration.UnitsFormatStyle(
            allowedUnits: [.minutes, .seconds], width: .wide, fractionalPart: .hide(rounded: .up)
        )
        return WatchWorkoutCopy.restRemaining(time.locale(locale).format(left), locale: locale)
    }
}

nonisolated extension WatchPresentation {
    /// The ring's length, the prototype's `stroke-dasharray` (r 88).
    static let ringLength = 553.0

    /// The rest screen at `now` in `mode`; nil in a mode that shows no rest. The time left and the ring's share are
    /// the Domain's (`RestTimer.remaining(at:)`, `fraction(at:)`): `553 − 553 × remaining / total`, so "+30s" grows
    /// `total` and the ring rescales. The next set is the active row, which the engine's cursor has already moved to
    /// when the rest begins (rule 20), in the workout's unit.
    static func rest(_ state: WorkoutState, mode: WatchMode, at now: Date, _ input: WatchLiveInput) -> WatchRestModel? {
        let rest: RestTimer, isOver: Bool
        switch mode {
        case let .rest(timer): (rest, isOver) = (timer, false)
        case let .restOver(timer): (rest, isOver) = (timer, true)
        case .idle, .ready, .summary: return nil
        }
        return WatchRestModel(
            title: isOver ? WatchWorkoutCopy.goTitle : WatchWorkoutCopy.rest,
            isOver: isOver,
            clock: ClockText.remaining(rest.remaining(at: now)),
            endsAt: rest.endsAt,
            timer: rest,
            ringOffset: ringLength - ringLength * rest.fraction(at: now),
            heartRate: heartRate(input.heartRate, input.health),
            heartRateLine: heartRateLine(input.heartRate, input.health, locale: input.locale),
            next: nextLine(state, locale: input.locale),
            connection: connectionLine(input.connection, hasHeardPhone: input.hasHeardPhone),
            locale: input.locale
        )
    }

    /// "Next: 185 lb × 5" for the active row, "Next exercise" when no set is left to log.
    static func nextLine(_ state: WorkoutState, locale: Locale) -> String {
        guard let active = activeRow(of: state), let index = active.set else {
            return WatchWorkoutCopy.nextExercise
        }
        let set = state.exercises[active.exercise].sets[index]
        return WatchWorkoutCopy.next(
            weight: set.weight.formatted(in: state.units), reps: set.reps.value, units: state.units, locale: locale
        )
    }
}
