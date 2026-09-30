import Foundation

/// A haptic the device should play (spec §4.5).
public enum Haptic: String, Hashable, Codable, Sendable, CaseIterable {
    case setLogged
    /// Played by the device at rest zero (F18); the engine never emits it, because rest reaching
    /// zero is not an event.
    case restOver
    /// Played after materialisation finds a PR (F05); the engine has no history to detect one.
    case personalRecord
    case workoutFinished
}

/// A side effect, returned as a value for the caller to run in order (ADR-004 rule 1). The host runs
/// `WorkoutEngine.reduce`'s effects for an envelope it created, and `WorkoutEngine.effects(from:to:)`
/// when it rebuilds for envelopes it received (the host loop on `WorkoutEngine.reduce`).
///
/// `.persist` comes before `.transmit`, so a device stores an envelope it created before any peer can
/// see it. Its next `seq` is `WorkoutEventStore.highestSeq` + 1, so it never reuses a transmitted one.
public enum Effect: Hashable, Sendable {
    case haptic(Haptic)
    /// Replaces any scheduled rest-over notification.
    case scheduleRestNotification(endsAt: Date)
    case cancelRestNotification
    case updateLiveActivity
    /// Append an envelope this device created to the local log (`WorkoutEventStore`). Only `reduce`
    /// emits it, for the host's own envelopes: the host appends every envelope it receives itself,
    /// before it rebuilds, whatever the envelope holds.
    case persist(EventEnvelope)
    /// Send the envelope to the peer. The session actor sends only its own device's envelopes (F17).
    case transmit(EventEnvelope)
    /// Rule 31: store the finished workout from its final state. F05 writes its sets and program
    /// updates, and computes the receipt with PRs from history (`WorkoutEngine.summary`). It is an
    /// idempotent upsert keyed by `WorkoutID`: `WorkoutEngine.effects(from:to:)` emits it again when a
    /// late envelope changes what the finished log replays to.
    case materialize(WorkoutState)
    /// Rule 32: drop the discarded workout's log.
    case discardLog
}
