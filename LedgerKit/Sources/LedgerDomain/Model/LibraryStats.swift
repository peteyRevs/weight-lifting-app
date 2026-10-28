import Foundation

/// What the Library shows of the history (F12): the exercises logged last, how many sessions hold each of them, and
/// every exercise's best set, as `StatsQueries.observeLibraryStats(recentLimit:)` emits them (F12 S3, N20).
public struct LibraryStats: Hashable, Sendable {
    /// `StatsQueries.recentlyLogged(limit:)`: the latest first.
    public let recent: [ExerciseID]
    /// `StatsQueries.sessionCount(exerciseID:)` of each recent exercise.
    public let sessions: [ExerciseID: Int]
    /// `StatsQueries.bestSets()`.
    public let bestSets: [ExerciseID: BestSet]

    public init(recent: [ExerciseID], sessions: [ExerciseID: Int], bestSets: [ExerciseID: BestSet]) {
        self.recent = recent
        self.sessions = sessions
        self.bestSets = bestSets
    }
}
