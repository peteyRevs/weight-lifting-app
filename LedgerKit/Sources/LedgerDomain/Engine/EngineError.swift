import Foundation

/// Why a live-workout log refused an envelope (ADR-004).
///
/// The reducer itself never fails: rules 1, 2 and 11 ignore envelopes that do not apply.
public enum EngineError: Error, Equatable, Sendable {
    /// A different envelope with this key is already in the log: a device reused a `seq`.
    /// `WorkoutEngine.replay` relies on a key naming exactly one envelope, so a `WorkoutEventStore`
    /// throws this rather than silently keep one of the two.
    case conflictingEnvelope(EnvelopeKey)
}
