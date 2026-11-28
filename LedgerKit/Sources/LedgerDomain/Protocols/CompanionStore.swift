import Foundation

/// What each device keeps for companion sync (F19): implemented over GRDB in LedgerPersistence (`v003_companionSync`)
/// and in memory in LedgerFakes (ADR-008); `CompanionStoreContract` in LedgerTestSupport pins it.
///
/// - **Finished logs**, one table on both devices (Q6/7): the watch's outbox, each record kept until the phone
///   acknowledges it, then compacted; and the phone's archive of its own log of a workout the watch took part in,
///   kept until the watch's record arrives, or for `FinishedLogEntry.archiveRetention`.
/// - **State**: the last context sent (phone) or applied (watch), and the last program file's hash.
/// - **Last performance**: the watch's copy of the phone's lines, replaced whole by each program file.
///
/// Dates and weights pass `StorageBoundary` (`RepositoryError.nonFiniteDate`, `.inexactWeight`), and records and
/// contexts are kept as their `CompanionCodec` bytes (`CompanionCodecError`): a refused value stores nothing.
public protocol CompanionStore: Sendable {
    /// Stores `record` as its workout's finished log, created `createdAt`. A workout already stored gets the new
    /// record (and its HealthKit UUID); its `createdAt`, `enqueuedAt` and acknowledgement stay.
    func saveFinishedLog(_ record: FinishedWorkoutRecord, createdAt: Date) async throws
    /// Every finished log not yet acknowledged, enqueued or not, oldest `createdAt` first, then by workout id: the
    /// order the outbox sends them in (criterion 8: "in order").
    func unacknowledgedLogs() async throws -> [FinishedLogEntry]
    /// Stamps the logs of `workouts` enqueued at `date`. A log already enqueued, or not stored, is left as it is.
    func markEnqueued(_ workouts: [WorkoutID], at date: Date) async throws
    /// Marks the logs of `workouts` acknowledged at `date`: they leave `unacknowledgedLogs()` for good, a later save
    /// of one included. Every later context repeats the ids, so a second acknowledgement changes nothing; a workout
    /// not stored is ignored.
    func acknowledge(_ workouts: [WorkoutID], at date: Date) async throws
    /// Deletes every acknowledged log (F05 compaction).
    func compactAcknowledged() async throws
    /// The phone's archive sweep (Q6/7): deletes every log created more than `archiveRetention` before `now`,
    /// acknowledged or not. A log exactly that old stays. Only the phone calls it: on the watch it would drop unsent
    /// workouts.
    func pruneArchives(now: Date) async throws
    /// The stored state, or `CompanionState.empty` before the first save.
    func state() async throws -> CompanionState
    /// Replaces the state whole.
    func saveState(_ state: CompanionState) async throws
    /// Replaces every stored last performance with `performance`, all or none.
    func replaceLastPerformance(_ performance: [ExerciseID: LastPerformance]) async throws
    /// Every stored last performance, exactly as saved.
    func lastPerformance() async throws -> [ExerciseID: LastPerformance]
}

/// A finished workout's log as `CompanionStore` keeps it.
public struct FinishedLogEntry: Hashable, Sendable {
    /// How long the phone keeps an archive whose record has not arrived (Q6/7): 14 days of 86 400 seconds.
    public static let archiveRetention: TimeInterval = 14 * 86400

    public var record: FinishedWorkoutRecord
    /// When the log was first stored.
    public var createdAt: Date
    /// When the outbox first handed it to the transport; nil until then (and always on the phone).
    public var enqueuedAt: Date?

    public init(record: FinishedWorkoutRecord, createdAt: Date, enqueuedAt: Date?) {
        self.record = record
        self.createdAt = createdAt
        self.enqueuedAt = enqueuedAt
    }
}

/// The companion state a device keeps between launches (F19 S5, S7a).
public struct CompanionState: Hashable, Sendable {
    /// The last context the phone sent, or the watch applied (criteria 1, 2): the watch's idle screen reads it.
    public var context: CompanionContext?
    /// The SHA-256 of the last program file sent (phone) or applied (watch), so an identical file is sent once.
    public var programFileSHA256: Data?

    public init(context: CompanionContext?, programFileSHA256: Data?) {
        self.context = context
        self.programFileSHA256 = programFileSHA256
    }

    /// Nothing stored yet.
    public static let empty = CompanionState(context: nil, programFileSHA256: nil)
}
