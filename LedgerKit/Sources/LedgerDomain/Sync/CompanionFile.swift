import Foundation

/// What travels as a file between the phone and the watch (F19; `transferFile`): anything too large for the context
/// or a user-info transfer.
public enum CompanionFile: Hashable, Codable, Sendable {
    /// Phone → watch: the active program, the custom exercises its slots name (the watch's catalog lacks them), and
    /// the last performance of each exercise it holds, for `SessionBuilder` on the watch.
    case program(Program, customExercises: [Exercise], lastPerformance: [ExerciseID: LastPerformance])
    /// Watch → phone: a finished workout whose record encodes to more than `CompanionCodec.userInfoLimit` bytes
    /// (criterion 8). It is the whole record, so the phone reconciles it as it would one that came as user info.
    case workoutLog(FinishedWorkoutRecord)
}

/// A workout finished on the watch, for the phone's history (F19; criteria 5–8): its whole event log, which the
/// phone merges with its own (`WorkoutReconciler`). It goes as user info, or as `CompanionFile.workoutLog` when
/// `CompanionCodec.delivery(for:)` says `.file`.
public struct FinishedWorkoutRecord: Hashable, Codable, Sendable {
    public var workoutID: WorkoutID
    /// Every envelope of the workout the watch holds, from every device.
    public var log: [EventEnvelope]
    /// The HealthKit workout the watch saved, which the phone reads its stats from once HealthKit has synced it
    /// (criterion 9); nil when the watch saved none (Health declined or failed).
    public var healthKitUUID: UUID?
    /// When the watch's workout ended.
    public var finishedAt: Date
    /// The watch that sent it.
    public var device: DeviceID

    public init(workoutID: WorkoutID, log: [EventEnvelope], healthKitUUID: UUID?, finishedAt: Date, device: DeviceID) {
        self.workoutID = workoutID
        self.log = log
        self.healthKitUUID = healthKitUUID
        self.finishedAt = finishedAt
        self.device = device
    }
}
