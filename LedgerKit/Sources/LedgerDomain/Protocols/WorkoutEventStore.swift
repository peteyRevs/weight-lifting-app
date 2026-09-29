import Foundation

/// The live workouts' envelope logs (ADR-004 rule 5). Declared here, implemented over GRDB in
/// LedgerPersistence (F05).
///
/// The host appends every envelope it receives for a workout before it reduces it, whatever the
/// effects, and appends its own through `Effect.persist`. So the store holds every envelope `replay`
/// may apply, including those `WorkoutEngine.reduce` ignores.
public protocol WorkoutEventStore: Sendable {
    /// Appends the envelopes. Idempotent on `EnvelopeKey` within a workout: an envelope already stored
    /// is skipped. Throws `EngineError.conflictingEnvelope` when a stored envelope with the same key
    /// differs (the precondition on `EventEnvelope`), and then stores nothing from the batch.
    ///
    /// Returns the envelopes it newly stored, in the order given. The host reduces exactly these, which
    /// is how it meets `WorkoutEngine.reduce`'s precondition that no envelope is reduced twice.
    func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope]
    /// Every stored envelope of the workout, in no particular order (`WorkoutEngine.replay` orders them).
    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope]
    /// The highest `seq` stored from `device` for the workout: the gap-replay handshake (F17), and the
    /// base of the device's own next `seq`.
    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64?
    /// Workouts whose log holds a `started` and no `finished` or `discarded` (resume on launch).
    func liveWorkoutIDs() async throws -> [WorkoutID]
    /// Workouts whose log holds a `finished` or `discarded` but has not been compacted. On launch the
    /// host replays each, materialises a finished one or drops a discarded one, then compacts it. This
    /// covers a kill after the terminal envelope is stored but before materialisation commits.
    func unmaterializedWorkoutIDs() async throws -> [WorkoutID]
    /// Deletes the workout's log once it is materialised (or discarded).
    func compact(workout: WorkoutID) async throws
}
