import Foundation

/// The live workouts' envelope logs (ADR-004 rule 5). Declared here, implemented over GRDB in
/// LedgerPersistence (F05).
public protocol WorkoutEventStore: Sendable {
    /// Appends the envelopes. Idempotent on `EnvelopeKey` within a workout: an envelope already stored
    /// is skipped. Throws `EngineError.conflictingEnvelope` when a stored envelope with the same key
    /// differs.
    func append(_ envelopes: [EventEnvelope]) async throws
    /// Every stored envelope of the workout, in no particular order (`WorkoutEngine.replay` orders them).
    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope]
    /// The highest `seq` stored from `device` for the workout (the gap-replay handshake, F17).
    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64?
    /// Workouts whose log holds a `started` and no `finished` or `discarded` (resume on launch).
    func liveWorkoutIDs() async throws -> [WorkoutID]
    /// Deletes the workout's log once it is materialised (or discarded).
    func compact(workout: WorkoutID) async throws
}
