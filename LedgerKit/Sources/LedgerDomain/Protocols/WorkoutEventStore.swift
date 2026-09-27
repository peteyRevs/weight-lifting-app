import Foundation

/// The live workout's envelope log (ADR-004). F02 reserves the name only; F04 replaces this file
/// with the full contract once `EventEnvelope` exists.
public protocol WorkoutEventStore: Sendable {}
