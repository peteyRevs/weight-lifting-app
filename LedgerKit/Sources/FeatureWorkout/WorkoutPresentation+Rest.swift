import Foundation
import LedgerDomain

nonisolated extension WorkoutPresentation {
    /// The rest panel at `now`, while the workout shows a rest. When a rest exists is the Domain's
    /// (`WorkoutState.shownRest`), and so are its time left and the ring's share (`remaining(at:)`,
    /// `fraction(at:)`): nothing here decides or counts. `now` is handed in by whoever holds the injected
    /// date. The time left is written as a countdown writes it, by the whole second, rounded up, so "0:00"
    /// and "Rest over" come together; VoiceOver is given the same seconds in words, in `locale`.
    ///
    /// The next set is the shown row (`activeSet`): a set that is logged hands the shown row to the
    /// engine's cursor, which has already moved on when the rest begins (rule 20), to the next exercise's
    /// first set where the logged one was its exercise's last. So the line always names a set that can be
    /// logged, and the prototype's "Set n · next exercise" has no case here.
    static func rest(
        _ state: WorkoutState,
        at now: Date,
        selection: WorkoutSelection?,
        isBusy: Bool,
        locale: Locale
    ) -> RestPanelModel? {
        guard let rest = state.shownRest else {
            return nil
        }
        let left = rest.remaining(at: now)
        let isOver = left <= .zero
        let words = Duration.UnitsFormatStyle(
            allowedUnits: [.minutes, .seconds], width: .wide, fractionalPart: .hide(rounded: .up)
        ).locale(locale)
        return RestPanelModel(
            clock: ClockText.remaining(left),
            fraction: rest.fraction(at: now),
            status: isOver ? WorkoutCopy.restOver : WorkoutCopy.resting,
            spokenTime: isOver ? "" : words.format(left),
            isOver: isOver,
            next: nextSet(of: state, selection: selection, locale: locale),
            extend: WorkoutCopy.extendRest,
            extendLabel: WorkoutCopy.extendRestLabel,
            skip: WorkoutCopy.skipRest,
            isEnabled: !isBusy
        )
    }

    /// The shown row of the shown exercise, as the panel names it: its number among the rows that are not
    /// drop sets, or "Drop set", then its weight in the workout's unit and its reps.
    private static func nextSet(
        of state: WorkoutState,
        selection: WorkoutSelection?,
        locale: Locale
    ) -> RestPanelModel.NextSet? {
        guard let shown = shownExercise(of: state, selection: selection),
              let active = activeSet(of: shown, in: state, selection),
              let index = state.exercises[shown].sets.firstIndex(where: { $0.id == active })
        else {
            return nil
        }
        let sets = state.exercises[shown].sets
        let set = sets[index]
        let isDrop = set.kind == .drop
        let number = sets[...index].count { $0.kind != .drop }
        let weight = set.weight.formatted(in: state.units)
        let spoken = [
            isDrop ? WorkoutCopy.spokenDropSet : WorkoutCopy.spokenSet(number, locale: locale),
            WorkoutCopy.spokenWeight(weight, units: state.units, locale: locale),
            WorkoutCopy.spokenReps(set.reps.value, locale: locale)
        ]
        return RestPanelModel.NextSet(
            line: WorkoutCopy.nextSet(
                number: isDrop ? nil : number, weight: weight, reps: set.reps.value, units: state.units,
                locale: locale
            ),
            spoken: spoken.joined(separator: ", ")
        )
    }
}
