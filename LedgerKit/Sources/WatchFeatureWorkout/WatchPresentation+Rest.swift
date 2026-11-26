import Foundation
import LedgerDomain

/// What the rest screen draws (spec §4.3 "Watch — rest timer", §4.5 as F18 resolves it).
nonisolated struct WatchRestModel: Equatable, Sendable {
    /// "REST" while the countdown runs, "GO" in the moment after it ends.
    let title: String
    /// "m:ss" left, rounded up as a countdown is; the screen counts down to `endsAt` by itself.
    let clock: String
    let endsAt: Date
    /// The ring's `stroke-dashoffset` on its 553 track: 0 at the start of the rest (full), 553 at its end (empty).
    let ringOffset: Double
    /// "142", or "—".
    let heartRate: String
    /// "Next: 185 lb × 5", or "Next exercise" when no set is left.
    let next: String
    let connection: String?
}

nonisolated extension WatchPresentation {
    /// The ring's length, the prototype's `stroke-dasharray` (r 88).
    static let ringLength = 553.0

    /// The rest screen at `now` in `mode`; nil in a mode that shows no rest. The time left and the ring's share are
    /// the Domain's (`RestTimer.remaining(at:)`, `fraction(at:)`): `553 − 553 × remaining / total`, so "+30s" grows
    /// `total` and the ring rescales. The next set is the active row, which the engine's cursor has already moved to
    /// when the rest begins (rule 20), in the workout's unit.
    static func rest(_ state: WorkoutState, mode: WatchMode, at now: Date, _ input: WatchLiveInput) -> WatchRestModel? {
        let rest: RestTimer, title: String
        switch mode {
        case let .rest(timer): (rest, title) = (timer, WatchWorkoutCopy.rest)
        case let .restOver(timer): (rest, title) = (timer, WatchWorkoutCopy.goTitle)
        case .idle, .ready, .summary: return nil
        }
        return WatchRestModel(
            title: title,
            clock: ClockText.remaining(rest.remaining(at: now)),
            endsAt: rest.endsAt,
            ringOffset: ringLength - ringLength * rest.fraction(at: now),
            heartRate: heartRate(input.heartRate, input.health),
            next: nextLine(state, locale: input.locale),
            connection: connectionLine(input.connection, hasHeardPhone: input.hasHeardPhone)
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
