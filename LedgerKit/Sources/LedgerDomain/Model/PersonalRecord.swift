import Foundation

/// The kind and value of a personal record (decision #3).
public enum PRKind: Hashable, Codable, Sendable {
    /// A new best Brzycki estimated 1RM (decision #4).
    case estimatedOneRepMax(Weight)
    /// A new best weight lifted for at least these reps.
    case weightAtReps(Weight, Reps)
}

/// A personal record set in a workout (decision #3, spec rule 41 "PR" tag).
public struct PersonalRecord: Hashable, Codable, Sendable {
    public let exerciseID: ExerciseID
    public let kind: PRKind
    /// The record it beat (`nil` only for records created outside `PersonalRecords.detect`).
    public let previous: PRKind?
    public let achievedAt: Date
    public let workoutID: WorkoutID

    public init(exerciseID: ExerciseID, kind: PRKind, previous: PRKind?, achievedAt: Date, workoutID: WorkoutID) {
        self.exerciseID = exerciseID
        self.kind = kind
        self.previous = previous
        self.achievedAt = achievedAt
        self.workoutID = workoutID
    }
}
