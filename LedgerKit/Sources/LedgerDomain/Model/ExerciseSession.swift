import Foundation

/// One stored workout's done sets of one exercise (`StatsQueries.exerciseSessions(exerciseID:)`, F12 S2): what an
/// exercise's history is folded from (`ExerciseHistory.make`).
public struct ExerciseSession: Hashable, Sendable {
    public let workoutID: WorkoutID
    /// When the workout started: its date (product decision #26).
    public let startedAt: Date
    /// The done sets of every kind: the rows that perform the exercise in row order, each row's in set order.
    public var sets: [LoggedSet]

    public init(workoutID: WorkoutID, startedAt: Date, sets: [LoggedSet]) {
        self.workoutID = workoutID
        self.startedAt = startedAt
        self.sets = sets
    }
}
