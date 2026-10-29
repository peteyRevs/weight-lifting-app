import Foundation

/// One stored workout with the personal records it holds as history stands now (F13 S2, N8): what
/// `WorkoutRepository.observeWorkout(id:)` emits for a past workout's detail.
public struct RecordedWorkout: Hashable, Sendable {
    /// As `workout(id:)` reads it.
    public let workout: WorkoutState
    /// The records it holds (product decision #27), by exercise id text, then the estimated 1RM before the weight at
    /// reps: an edit of an earlier workout can add one or take one away.
    public let records: [PersonalRecord]

    public init(workout: WorkoutState, records: [PersonalRecord]) {
        self.workout = workout
        self.records = records
    }
}
