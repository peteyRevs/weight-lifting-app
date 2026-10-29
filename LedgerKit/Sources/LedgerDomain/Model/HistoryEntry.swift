import Foundation

/// One stored workout as the History list shows it (F13 S1, N1): what `WorkoutRepository.historyEntries()` reads
/// from the workout's own row, with its totals as stored, and none of its exercises or sets.
public struct HistoryEntry: Identifiable, Hashable, Sendable {
    public let id: WorkoutID
    public let name: String
    public let tag: String
    public let isDeload: Bool
    /// When the workout started: its date, its day and its week (product decision #26).
    public let startedAt: Date
    /// From its start to its end.
    public let elapsed: Duration
    /// Rule 34: Σ weight × reps over its done sets.
    public let volume: Volume
    public let doneSets: Int
    public let totalSets: Int
    /// How many personal records the workout holds as history stands now (product decision #27).
    public let prCount: Int

    public init(
        id: WorkoutID,
        name: String,
        tag: String,
        isDeload: Bool,
        startedAt: Date,
        elapsed: Duration,
        volume: Volume,
        doneSets: Int,
        totalSets: Int,
        prCount: Int
    ) {
        self.id = id
        self.name = name
        self.tag = tag
        self.isDeload = isDeload
        self.startedAt = startedAt
        self.elapsed = elapsed
        self.volume = volume
        self.doneSets = doneSets
        self.totalSets = totalSets
        self.prCount = prCount
    }

    /// The entry of `workout`, with its totals computed from its sets, holding `prCount` records: what a stored
    /// workout's row says of it. A workout with no end has no length.
    public init(_ workout: WorkoutState, prCount: Int) {
        self.init(
            id: workout.id,
            name: workout.name,
            tag: workout.tag,
            isDeload: workout.isDeload,
            startedAt: workout.startedAt,
            // `elapsed(at:)` reads its argument only when the workout has no end.
            elapsed: workout.elapsed(at: workout.startedAt),
            volume: workout.volume,
            doneSets: workout.doneSets,
            totalSets: workout.totalSets,
            prCount: prCount
        )
    }
}
