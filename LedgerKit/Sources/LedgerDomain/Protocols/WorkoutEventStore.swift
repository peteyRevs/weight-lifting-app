import Foundation

/// The live workouts' envelope logs (ADR-004 rule 5). Declared here, implemented over GRDB in
/// LedgerPersistence (F05).
///
/// The host appends every envelope it receives for a workout before it rebuilds, whatever the envelope
/// holds, and appends its own through `Effect.persist`. So the store holds every envelope `replay` may
/// apply, including those `WorkoutEngine.reduce` ignores, malformed ones included: the store never
/// judges an envelope's contents, only its key.
public protocol WorkoutEventStore: Sendable {
    /// Appends the envelopes. Idempotent on `EnvelopeKey` within a workout: an envelope already stored
    /// is skipped. Throws `EngineError.conflictingEnvelope` when a stored envelope with the same key
    /// differs (the precondition on `EventEnvelope`), and then stores nothing from the batch.
    ///
    /// Returns the envelopes it newly stored, in the order given. When there are any, the host rebuilds
    /// with `WorkoutEngine.replay` of the stored log (the host loop on `WorkoutEngine.reduce`).
    func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope]
    /// Every stored envelope of the workout, in no particular order (`WorkoutEngine.replay` orders them),
    /// each once and exactly as appended: every date to full precision, because `<` and the conflict
    /// check compare them.
    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope]
    /// The highest `seq` stored from `device` for the workout: the gap-replay handshake (F17), and the
    /// base of the device's own next `seq`.
    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64?
    /// Every workout with a stored log that has not been compacted, whatever it holds.
    ///
    /// On launch the host classifies each by `WorkoutEngine.replay` of its log:
    /// - live: it resumes the workout;
    /// - finished or discarded: it materialises or drops it, then compacts it. This covers a kill
    ///   after the terminal envelope is stored but before materialisation commits;
    /// - `nil` (no usable `started`, for example after a lost message or a resend that followed a
    ///   compaction): it never compacts the log. It keeps it and asks the peer to resend (F17).
    ///
    /// The largest `wallClock` across these logs also restores the hybrid logical clock before the host
    /// stamps anything (ADR-004 amendment).
    func uncompactedWorkoutIDs() async throws -> [WorkoutID]
    /// Deletes the workout's log once it is materialised (or discarded).
    func compact(workout: WorkoutID) async throws
}
