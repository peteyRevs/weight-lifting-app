import Foundation

/// The live workout's reducer (ADR-004), shared by phone and watch. It folds `EventEnvelope`s into a
/// `WorkoutState` and returns side effects as values.
///
/// It is pure and reads no clock: time arrives in the events and envelopes, so every device that
/// folds the same envelopes in the same order computes the same state.
public enum WorkoutEngine {
    /// The longest rest the engine keeps (rule 9): one hour, twelve times rule 3's longest exercise
    /// rest. Every rest it writes has a `total` in `0 ... longestRest` and ends at most `longestRest`
    /// after it starts: at the envelope's `wallClock`, or at the set's `doneAt` for an automatic rest.
    /// Only a corrupt or hostile envelope reaches the bound. It is clamped rather than trapped on, so
    /// a stored envelope can always be replayed.
    public static let longestRest = Duration.seconds(60 * 60)

    /// Rules 1 and 2: the state after `envelope`, and what the caller should do about it.
    ///
    /// **Precondition:** the caller dedupes by `EnvelopeKey`. It reduces only the envelopes that
    /// `WorkoutEventStore.append` newly stored, because `reduce` keeps no log and a second
    /// `restExtended` would extend twice. ADR-004's idempotence law belongs to `replay`, which dedupes.
    ///
    /// The host appends every envelope it receives for the workout to its store before reducing it,
    /// whatever the effects: `replay` may apply an envelope that `reduce` ignores here (one that sorts
    /// before the `started` or before the terminal).
    ///
    /// These are ignored, returning `(state, [])`:
    /// - any envelope before a `started` (on `nil`);
    /// - a `started` whose snapshot is not live or is for another workout, and a second `started`;
    /// - an envelope for another workout;
    /// - anything after `finished` or `discarded`.
    ///
    /// Otherwise the effects are, in order:
    /// 1. `.persist` and `.transmit`, which the host runs only for an envelope it created. The envelope
    ///    belongs in every log even when it changes nothing here, because a peer may order it differently.
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
            guard let snapshot = snapshot(startedBy: envelope) else {
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

    /// Rule 1: the snapshot a usable `started` begins its workout with. It must be live and for the
    /// envelope's workout; any other envelope yields `nil`.
    static func snapshot(startedBy envelope: EventEnvelope) -> WorkoutState? {
        guard case let .started(snapshot) = envelope.event,
              snapshot.phase == .live,
              snapshot.id == envelope.workoutID
        else {
            return nil
        }
        return snapshot
    }

    /// Rule 31: the receipt of a finished workout. F05 computes it from the state `.materialize` carries.
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
