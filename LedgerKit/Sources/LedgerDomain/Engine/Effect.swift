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

/// A side effect of reducing an envelope, returned as a value for the caller to run (ADR-004 rule 1).
public enum Effect: Hashable, Sendable {
    case haptic(Haptic)
    /// Replaces any scheduled rest-over notification.
    case scheduleRestNotification(endsAt: Date)
    case cancelRestNotification
    case updateLiveActivity
    /// Append the envelope to the local log (`WorkoutEventStore`).
    case persist(EventEnvelope)
    /// Send the envelope to the peer. The session actor sends only its own device's envelopes (F17).
    case transmit(EventEnvelope)
    /// Rule 31: store the finished workout. PRs are empty here and computed from history by F05.
    case materialize(WorkoutSummary)
    /// Rule 32: drop the discarded workout's log.
    case discardLog
}
