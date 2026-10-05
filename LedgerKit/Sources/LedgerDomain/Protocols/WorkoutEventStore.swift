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
    /// differs (the precondition on `EventEnvelope`), and then stores nothing from the batch. A stored
    /// envelope this app version cannot read is repaired: the incoming one takes its place and counts as
    /// newly stored (F05).
    ///
    /// Returns the envelopes it newly stored, in the order given. When there are any, the host rebuilds
    /// with `WorkoutEngine.replay` of the stored log (the host loop on `WorkoutEngine.reduce`).
    func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope]
    /// Every stored envelope of the workout, in no particular order (`WorkoutEngine.replay` orders them),
    /// each once and exactly as appended: every date to full precision, because `<` and the conflict
    /// check compare them. A stored envelope this app version cannot read is left out and counted by
    /// `unreadableCount(for:)`.
    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope]
    /// How many of the workout's stored envelopes this app version cannot read: one written in a later
    /// payload version, or damaged (F05). The store keeps each until a readable copy of it is appended, or
    /// a later version reads it. While the count is above zero the log is incomplete: the host resumes from
    /// what it can read, but never materialises or compacts the log (F17, "Inputs from F05").
    ///
    /// No default: a store that keeps envelopes as values returns 0, and a wrapper must forward the call,
    /// or the host would compact rows it cannot see.
    func unreadableCount(for workout: WorkoutID) async throws -> Int
    /// The highest `seq` stored from `device` for the workout: the gap-replay handshake (F17), and the
    /// base of the device's own next `seq`.
    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64?
    /// Every workout with a stored log that has not been compacted, whatever it holds.
    ///
    /// On launch the host classifies each by `WorkoutEngine.replay` of its log:
    /// - live: it resumes the workout;
    /// - finished: it materialises it, and the log goes with the save
    ///   (`WorkoutRepository.materialize(_:slotUpdates:droppingLog:)`) or, where the two stores are not one
    ///   database, is compacted after it: the host looks here after every save, and compacts what it still
    ///   finds; discarded: it compacts it. This covers a kill after the terminal envelope is stored but
    ///   before materialisation commits;
    /// - `nil` (no usable `started`, for example after a lost message or a resend that followed a
    ///   compaction): it never compacts the log. It keeps it and asks the peer to resend (F17).
    ///
    /// The largest `wallClock` across these logs also restores the hybrid logical clock before the host
    /// stamps anything (ADR-004 amendment): `newestWallClock()`.
    func uncompactedWorkoutIDs() async throws -> [WorkoutID]
    /// The largest finite `wallClock` stored in any uncompacted log, unreadable envelopes included, or
    /// `nil` when there is none: the hybrid logical clock's `newest` on launch (ADR-004 amendment,
    /// "Recovery on launch"; F17, "Inputs from F05").
    func newestWallClock() async throws -> Date?
    /// Deletes the workout's log: once it is discarded, or once it is materialised and still here, because
    /// the repository could not drop it with the save or dropped another store's
    /// (`WorkoutRepository.materialize(_:slotUpdates:droppingLog:)`). Deleting a log that is gone does nothing.
    func compact(workout: WorkoutID) async throws
}

public extension WorkoutEventStore {
    /// The largest finite stamp among `envelopes(for:)` of every uncompacted log. Right for a store whose
    /// envelopes are all readable; a store that can hold unreadable ones reads their stamps too.
    func newestWallClock() async throws -> Date? {
        var newest: Date?
        for workout in try await uncompactedWorkoutIDs() {
            let stamps = try await envelopes(for: workout).map(\.wallClock)
            for stamp in stamps where stamp.timeIntervalSinceReferenceDate.isFinite {
                newest = max(newest ?? stamp, stamp)
            }
        }
        return newest
    }
}
