import Foundation

// The values `HealthStore` trades in (F16). Foundation only: LedgerHealth maps them to HealthKit's types.

/// The sharing status for workouts (HealthKit reports no read status); `unavailable`: no HealthKit on the device.
public enum HealthAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied, unavailable
}

/// What a finished workout writes to Health as metadata, beside HealthKit's own samples.
public struct HealthWorkoutMetadata: Equatable, Sendable {
    public let workoutID: WorkoutID
    public let programName: String?
    public let dayName: String?
    public let totalVolume: Weight
    public let doneSets: Int

    public init(workoutID: WorkoutID, programName: String?, dayName: String?, totalVolume: Weight, doneSets: Int) {
        self.workoutID = workoutID
        self.programName = programName
        self.dayName = dayName
        self.totalVolume = totalVolume
        self.doneSets = doneSets
    }

    /// The volume as `com.petearevalo.Ledger.totalVolumeGrams` stores it: exact grams, in any unit (ADR-007).
    public var totalVolumeGrams: Decimal {
        totalVolume.grams
    }
}

/// The workout HealthKit saved, as the `workout_health` row keeps it (F05). A phone-only save has no heart rate.
public struct HealthWorkoutRecord: Equatable, Sendable, Codable {
    public let healthKitUUID: UUID
    public let start: Date
    public let end: Date
    public let avgHeartRate: Int?
    public let maxHeartRate: Int?
    public let activeEnergyKcal: Int?

    public init(
        healthKitUUID: UUID,
        start: Date,
        end: Date,
        avgHeartRate: Int?,
        maxHeartRate: Int?,
        activeEnergyKcal: Int?
    ) {
        self.healthKitUUID = healthKitUUID
        self.start = start
        self.end = end
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKcal = activeEnergyKcal
    }
}

/// One heart-rate reading from the wrist, in beats per minute. Never logged (engineering-standards §8).
public struct HeartRateSample: Equatable, Sendable {
    public let bpm: Int
    public let date: Date

    public init(bpm: Int, date: Date) {
        self.bpm = bpm
        self.date = date
    }
}

/// What happens to the HealthKit session, in the order it happens (`HealthStore.events`).
public enum HealthSessionEvent: Equatable, Sendable {
    case prepared
    case running(since: Date)
    case ended(Date)
    /// Another app's workout session took over and HealthKit ended ours (`errorAnotherWorkoutSessionStarted`,
    /// R1 §2.3). Nothing is written to Health; the workout's log carries on.
    case anotherWorkoutSessionStarted
    case mirrorConnected
    case mirrorDisconnected
    /// A session the system ended with the app was taken up again (`recoverActiveWorkoutSession`).
    case recovered
    /// The phone asked the watch to start (`WKApplicationDelegate.handle(_:)`).
    case startRequestedByPhone
    case failed(HealthError)
}

/// Every way a `HealthStore` call fails. No case carries `NSError` text: a screen maps each to copy (criterion 14).
public enum HealthError: Error, Equatable, Sendable {
    case notAuthorized
    case unavailable
    case sessionAlreadyRunning
    case noActiveSession
    case anotherWorkoutSessionStarted
    case watchAppUnavailable
    case mirroringTimedOut
    /// A HealthKit error none of the cases names, by its code alone.
    case underlying(code: Int)
}
