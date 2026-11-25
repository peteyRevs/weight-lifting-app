import Foundation

/// HealthKit, behind one protocol (architecture §9; F16): `LiveHealthStore` in LedgerHealth and
/// `FakeHealthStore` in LedgerFakes. The watch runs the workout session; the phone asks the watch to start,
/// mirrors its session, and saves a workout itself only when no watch took part.
///
/// Every failure is a `HealthError`.
public protocol HealthStore: Sendable {
    /// The sharing status for workouts now. Never asks the lifter.
    func authorization() async -> HealthAuthorization
    /// Asks for workouts, heart rate and active energy, once: on the phone at the first "Start workout", which
    /// prompts for both devices.
    func requestAuthorization() async throws -> HealthAuthorization
    /// Everything that happens to the session, in order, for the life of the store. One consumer.
    var events: AsyncStream<HealthSessionEvent> { get }

    // MARK: Watch: the primary session

    /// Prepares a session and starts it at `start`: `.prepared`, then mirroring to the phone (non-fatal if it
    /// times out), then `.running`.
    func startSession(workoutID: WorkoutID, at start: Date) async throws
    /// The running session's heart rate, in arrival order, for as long as the caller keeps the stream.
    func heartRate() async -> AsyncStream<HeartRateSample>
    /// Ends the session at `end`, writes the workout with `metadata` to Health and returns what was saved.
    func endSession(metadata: HealthWorkoutMetadata, at end: Date) async throws -> HealthWorkoutRecord
    /// Ends the session and writes nothing to Health.
    func discardSession() async throws
    /// Takes up a session the system ended with the app. `true` when there was one.
    func recoverActiveSession() async throws -> Bool
    /// The phone asked the watch to start (`WKApplicationDelegate.handle(_:)`): reported as
    /// `.startRequestedByPhone`, for the watch's workout screen to start the session.
    func noteStartRequestedByPhone()

    // MARK: Phone

    /// Opens the watch app with a session running (`startWatchApp(toHandle:)`).
    func requestWatchStart() async throws
    /// Saves a workout logged on the phone alone, with no heart rate. Never used for a workout a watch took
    /// part in: the watch writes that one.
    func saveWorkout(metadata: HealthWorkoutMetadata, start: Date, end: Date) async throws -> HealthWorkoutRecord
    /// The saved workout with `healthKitUUID`, with its heart-rate statistics, or nil if Health has none.
    func workoutRecord(healthKitUUID: UUID) async throws -> HealthWorkoutRecord?
    /// The mirrored session's data channel, rebound to the newest mirrored session (F17's transport).
    var remoteChannel: any RemoteSessionChannel { get }
}
