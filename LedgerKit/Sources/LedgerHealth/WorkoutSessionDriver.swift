import Foundation
import LedgerDomain

// The seam between `LiveHealthStore` and HealthKit (F16 S2a): the store's state machine drives these protocols, the
// tests script them, so that no test touches HealthKit (testing-strategy §3), and from S2b the watch implements them
// over `HKWorkoutSession` + `HKLiveWorkoutBuilder`, with the end, the metadata and recovery. Every value crossing
// the seam is Sendable and HealthKit-free; each conformer maps HealthKit's errors to `HealthError` before they
// cross.

/// `HKWorkoutSessionState`, as far as the store waits on it.
enum WorkoutSessionState: Equatable, Sendable {
    case notStarted, prepared, running, paused, stopped, ended
}

/// What the session's and the builder's delegates report, in the order they report it.
enum WorkoutSessionCallback: Equatable, Sendable {
    /// `workoutSession(_:didChangeTo:from:date:)`.
    case state(WorkoutSessionState, Date)
    /// `workoutSession(_:didFailWithError:)`.
    case failed(HealthError)
    /// `workoutBuilder(_:didCollectDataOf:)`, the most recent heart-rate quantity.
    case heartRate(HeartRateSample)
    /// `workoutSession(_:didDisconnectFromRemoteDeviceWithError:)`: the phone's mirror dropped.
    case mirrorDisconnected
}

/// One workout session and its live builder, set up (configuration, session, builder, data source, delegates)
/// and not yet prepared. Each call is the HealthKit call of the same name.
protocol WorkoutSessionDriver: Sendable {
    /// Every delegate callback, for the life of the session. One consumer: the store.
    var callbacks: AsyncStream<WorkoutSessionCallback> { get }
    func prepare()
    /// Returns, or throws `CancellationError`, as soon as its task is cancelled, whatever HealthKit does: it can
    /// hang on a reconnect (R1 §2.5 gotcha 5), and the store's timeout must not wait for it.
    func startMirroring() async throws
    func startActivity(at date: Date)
    func beginCollection(at date: Date) async throws
    func end()
    func discardWorkout()
}

/// Where the store's sessions and its authorization come from: HealthKit, or a test's script.
protocol WorkoutSessionProvider: Sendable {
    func authorization() async -> HealthAuthorization
    /// Asks for workouts, heart rate and active energy, and returns the answer.
    func requestAuthorization() async throws -> HealthAuthorization
    /// A new session for a strength workout, set up and not yet prepared.
    func makeSession() throws -> any WorkoutSessionDriver
}
