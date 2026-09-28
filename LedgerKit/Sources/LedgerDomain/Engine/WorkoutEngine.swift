import Foundation

/// The live workout's reducer (ADR-004), shared by phone and watch. It folds `EventEnvelope`s into a
/// `WorkoutState` and returns side effects as values.
///
/// It is pure and reads no clock: time arrives in the events and envelopes, so every device that
/// folds the same envelopes in the same order computes the same state.
public enum WorkoutEngine {
    /// Rules 1 and 2: the state after `envelope`, and what the caller should do about it.
    ///
    /// These are ignored, returning `(state, [])`:
    /// - any envelope before a `started` (on `nil`);
    /// - a `started` whose snapshot is not live or is for another workout, and a second `started`;
    /// - an envelope for another workout;
    /// - anything after `finished` or `discarded`.
    ///
    /// Otherwise the effects are, in order:
    /// 1. `.persist` and `.transmit`. The envelope belongs in every log even when it changes nothing
    ///    here, because a peer may order it differently.
    /// 2. The event's own effects (rules 3, 9 and 10).
    /// 3. `.updateLiveActivity` when the state changed.
    public static func reduce(_ state: WorkoutState?, _ envelope: EventEnvelope) -> (WorkoutState?, [Effect]) {
        var next = state
        guard let effects = step(&next, envelope) else {
            return (state, [])
        }
        let changed: [Effect] = next == state ? [] : [.updateLiveActivity]
        return (next, [.persist(envelope), .transmit(envelope)] + effects + changed)
    }

    /// `reduce`'s transition, in place: applies an accepted envelope to `state` and returns the
    /// event's own effects, or returns `nil` and leaves `state` alone when the envelope is ignored.
    /// `replay` folds with it directly, so a rebuild never copies the state per envelope.
    static func step(_ state: inout WorkoutState?, _ envelope: EventEnvelope) -> [Effect]? {
        guard state != nil else {
            guard case let .started(snapshot) = envelope.event,
                  snapshot.phase == .live,
                  snapshot.id == envelope.workoutID
            else {
                return nil
            }
            state = snapshot
            return []
        }
        guard state?.phase == .live, state?.id == envelope.workoutID else {
            return nil
        }
        return apply(envelope.event, to: &state, at: envelope.wallClock)
    }

    /// Rule 31: the receipt of a finished workout.
    ///
    /// Elapsed time is frozen at `endedAt` (zero for a workout that has not ended). `prs` come from
    /// the caller, which detects them against history (decision #3). There is one row per exercise,
    /// in the workout's units.
    public static func summary(_ state: WorkoutState, prs: [PersonalRecord]) -> WorkoutSummary {
        WorkoutSummary(
            workoutID: state.id,
            elapsed: state.elapsed(at: state.endedAt ?? state.startedAt),
            doneSets: state.doneSets,
            totalSets: state.totalSets,
            volume: state.volume,
            prs: prs,
            rows: state.exercises.map { ReceiptRow(exercise: $0, units: state.units) }
        )
    }
}
