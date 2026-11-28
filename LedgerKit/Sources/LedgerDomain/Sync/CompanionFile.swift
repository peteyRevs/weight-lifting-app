import Foundation

/// What travels as a file between the phone and the watch (F19; `transferFile`): anything too large for the context
/// or a user-info transfer.
///
/// Its encoding is canonical: equal files give the same bytes in every process, so the phone can tell an unchanged
/// program file by its SHA-256 (S5). A dictionary keyed by an id, which JSON writes as key-value pairs in the
/// dictionary's own order, is written in id order here; `Slot` writes its misses in order for the same reason.
public enum CompanionFile: Hashable, Codable, Sendable {
    /// Phone → watch: the active program, the custom exercises its slots name (the watch's catalog lacks them), and
    /// the last performance of each exercise it holds, for `SessionBuilder` on the watch.
    case program(Program, customExercises: [Exercise], lastPerformance: [ExerciseID: LastPerformance])
    /// Watch → phone: a finished workout whose record encodes to more than `CompanionCodec.userInfoLimit` bytes
    /// (criterion 8). It is the whole record, so the phone reconciles it as it would one that came as user info.
    case workoutLog(FinishedWorkoutRecord)

    /// The keys Swift synthesizes for these cases, declared so that `encode(to:)` can use them; `init(from:)` stays
    /// synthesized.
    private enum CodingKeys: String, CodingKey {
        case program, workoutLog
    }

    private enum ProgramCodingKeys: String, CodingKey {
        case _0, customExercises, lastPerformance // swiftlint:disable:this identifier_name
    }

    private enum WorkoutLogCodingKeys: String, CodingKey {
        case _0 // swiftlint:disable:this identifier_name
    }

    /// The synthesized encoding, with `lastPerformance`'s pairs in id order: key, value, key, value, as JSON writes
    /// a dictionary whose key is not a string, so the synthesized decoding reads it.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .program(program, customExercises, lastPerformance):
            var fields = container.nestedContainer(keyedBy: ProgramCodingKeys.self, forKey: .program)
            try fields.encode(program, forKey: ._0)
            try fields.encode(customExercises, forKey: .customExercises)
            var pairs = fields.nestedUnkeyedContainer(forKey: .lastPerformance)
            for (id, line) in lastPerformance.sorted(by: { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }) {
                try pairs.encode(id)
                try pairs.encode(line)
            }
        case let .workoutLog(record):
            var fields = container.nestedContainer(keyedBy: WorkoutLogCodingKeys.self, forKey: .workoutLog)
            try fields.encode(record, forKey: ._0)
        }
    }
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
