import Foundation

/// The live workout's reducer (ADR-004), shared by phone and watch. It folds `EventEnvelope`s into a
/// `WorkoutState` and returns side effects as values.
///
/// It is pure and reads no clock: time arrives in the events (the clock rule on `WorkoutEvent`), so
/// every device that folds the same envelopes in the same order computes the same state.
public enum WorkoutEngine {
    /// The longest rest the engine keeps (rule 9): one hour, twelve times rule 3's longest exercise
    /// rest. Every rest in a state it folds has a `total` in `0 ... longestRest`:
    /// - `EventEnvelope.isWellFormed` rejects a `restStarted`, a "+30s" or a `started` snapshot whose rest
    ///   length is outside it;
    /// - an automatic rest is at most rule 3's 300 s, from the set's `doneAt`;
    /// - "+30s" on a shown rest saturates its `total` at the bound, and holds its end to at most
    ///   `longestRest` after `tappedAt`.
    public static let longestRest = Duration.seconds(60 * 60)

    /// Rules 1 and 2: the state after `envelope`, and what the caller should do about it.
    ///
    /// **The host loop (ADR-004 rule 2).** `reduce` keeps no log, so it must never see an envelope
    /// twice: a second "+30s" would extend again. ADR-004's idempotence law belongs to `replay`, which
    /// dedupes. So the host (F17):
    /// 1. Appends every envelope it receives for the workout to its `WorkoutEventStore` first, whatever
    ///    the effects: `replay` may apply an envelope that `reduce` ignores here (one that sorts before
    ///    the `started` or before the terminal).
    /// 2. Takes what `append` newly stored. If every one of those envelopes sorts after the newest
    ///    envelope already applied, it reduces them in sort order. Otherwise it rebuilds once, with
    ///    `replay` of the stored log. That log already holds the whole batch, so reducing any envelope
    ///    of the batch after the rebuild would apply it twice.
    /// 3. Runs `effects(from:to:)` of the state before and after, and only those, for what it received.
    ///    It runs the effects below only for an envelope it created, which the hybrid logical clock
    ///    sorts after everything it holds.
    ///
    /// These are ignored, returning `(state, [])`:
    /// - a malformed envelope (`EventEnvelope.isWellFormed`);
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
        guard envelope.isWellFormed, let effects = step(&next, envelope) else {
            return (state, [])
        }
        let changed: [Effect] = next == state ? [] : [.updateLiveActivity]
        return (next, [.persist(envelope), .transmit(envelope)] + effects + changed)
    }

    /// `reduce`'s transition for a well-formed envelope, in place: applies an accepted envelope to
    /// `state` and returns the event's own effects, or returns `nil` and leaves `state` alone when the
    /// envelope is ignored. `replay` folds with it directly, so a rebuild never copies the state per
    /// envelope.
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
        return apply(envelope.event, to: &state)
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
