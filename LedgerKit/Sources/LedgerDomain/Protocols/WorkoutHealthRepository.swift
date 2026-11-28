import Foundation

/// HealthKit's statistics for the finished workouts (F19 S3b, criterion 9): the `workout_health` row, at most one per
/// workout. `GRDBWorkoutRepository` and `InMemoryWorkoutRepository` keep it beside the workouts they store, and
/// `WorkoutHealthContract` in LedgerTestSupport pins it. It is a protocol of its own rather than part of
/// `WorkoutRepository`, so the history doubles need not stub it.
///
/// The HealthKit UUID a workout waits on lives in its finished log (`CompanionStore`, `finished_log.health_uuid`):
/// the phone stores the watch's record there when it arrives (`saveFinishedLog`) and keeps it until the archive sweep,
/// 14 days, so the retry (F19 S6b, launch, foreground and each arrival, for at most 24 hours from the log's
/// `createdAt`) needs no table of its own.
public protocol WorkoutHealthRepository: Sendable {
    /// Stores `health` as the statistics of `workout`, replacing every field of any stored ones, a nil included.
    /// A workout that is not stored, or is deleted, throws `RepositoryError.missingRow` and stores nothing.
    func saveHealth(_ health: WorkoutHealth, of workout: WorkoutID) async throws
    /// The statistics stored for `workout`, or nil. A deleted workout keeps them, as it keeps its rows.
    func health(of workout: WorkoutID) async throws -> WorkoutHealth?
    /// Every stored, live workout whose finished log names a HealthKit UUID and that has no statistics yet,
    /// acknowledged or not: oldest log first, then by workout id. A log of a workout not stored (yet) is left out.
    func pendingHealth() async throws -> [PendingHealth]
}

/// A workout's `workout_health` row. A phone-only save has no heart rate.
public struct WorkoutHealth: Hashable, Sendable {
    public var healthKitUUID: UUID
    public var avgHeartRate: Int?
    public var maxHeartRate: Int?
    public var activeEnergyKcal: Int?

    public init(healthKitUUID: UUID, avgHeartRate: Int?, maxHeartRate: Int?, activeEnergyKcal: Int?) {
        self.healthKitUUID = healthKitUUID
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKcal = activeEnergyKcal
    }

    /// What `HealthStore.workoutRecord(healthKitUUID:)` read, without the dates the workout's own row holds.
    public init(_ record: HealthWorkoutRecord) {
        self.init(
            healthKitUUID: record.healthKitUUID,
            avgHeartRate: record.avgHeartRate,
            maxHeartRate: record.maxHeartRate,
            activeEnergyKcal: record.activeEnergyKcal
        )
    }
}

/// A workout waiting for its HealthKit statistics (`WorkoutHealthRepository.pendingHealth()`).
public struct PendingHealth: Hashable, Sendable {
    public var workoutID: WorkoutID
    public var healthKitUUID: UUID
    /// When its finished log was first stored: the retry gives up 24 hours after it.
    public var createdAt: Date

    public init(workoutID: WorkoutID, healthKitUUID: UUID, createdAt: Date) {
        self.workoutID = workoutID
        self.healthKitUUID = healthKitUUID
        self.createdAt = createdAt
    }
}
