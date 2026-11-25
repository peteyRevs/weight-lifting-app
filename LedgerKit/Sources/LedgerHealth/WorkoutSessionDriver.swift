import Foundation
import LedgerDomain

// The seam between `LiveHealthStore` and HealthKit (F16 S2a, S2b): the store's state machine drives these protocols,
// the
// watch's `HealthKitWorkoutSession` implements them over `HKWorkoutSession` + `HKLiveWorkoutBuilder`, and the tests
// script them, so that no test touches HealthKit (testing-strategy §3). Every value crossing the seam is Sendable
// and HealthKit-free; each conformer maps HealthKit's errors to `HealthError` before they cross.

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
    /// `workoutSession(_:didReceiveDataFromRemoteWorkoutSession:)`.
    case received([Data])
}

/// A metadata value `HKWorkoutBuilder.addMetadata` takes: text, or a mass in grams, exact until the conformer
/// makes it an `HKQuantity` (ADR-007).
enum HealthMetadataValue: Equatable, Sendable {
    case text(String)
    case grams(Decimal)
}

/// The workout `finishWorkout()` wrote, with the builder's statistics for it.
struct FinishedWorkout: Equatable, Sendable {
    let uuid: UUID
    let start: Date
    let end: Date
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let activeEnergyKcal: Int?
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
    func stopActivity(at date: Date)
    func endCollection(at date: Date) async throws
    func addMetadata(_ metadata: [String: HealthMetadataValue]) async throws
    func finishWorkout() async throws -> FinishedWorkout
    func end()
    func discardWorkout()
    /// `sendToRemoteWorkoutSession(data:)`.
    func send(_ data: Data) async throws
}

/// Where the store's sessions and its authorization come from: HealthKit, or a test's script.
protocol WorkoutSessionProvider: Sendable {
    func authorization() async -> HealthAuthorization
    /// Asks for `HealthTypeSet`'s types and returns the answer.
    func requestAuthorization() async throws -> HealthAuthorization
    /// A new session for a strength workout, set up and not yet prepared.
    func makeSession() throws -> any WorkoutSessionDriver
    /// The session the system kept running after the app ended, with its builder, data source and delegates
    /// attached again; nil when there is none.
    func recoverSession() async throws -> (any WorkoutSessionDriver)?
}

// The phone's half of the seam (F16 S3): its mirrored sessions, and the HealthKit calls only the phone makes.

/// What happens to the phone's mirrored sessions, in order.
enum MirrorEvent: Equatable, Sendable {
    /// `workoutSessionMirroringStartHandler` handed over a session (or recovery took one up): it is the newest.
    case connected
    /// A session's `didDisconnectFromRemoteDeviceWithError`: that session is dropped.
    case disconnected
    /// A session's `didReceiveDataFromRemoteWorkoutSession`.
    case received([Data])
}

/// The phone's end of mirroring: `MirroringStartRegistrar`, or a test's script.
protocol MirrorReceiver: Sendable {
    /// Every mirrored session's events, for the life of the receiver. One consumer: the store.
    var mirrorEvents: AsyncStream<MirrorEvent> { get }
    /// Sends over the newest mirrored session; `noActiveSession` when none is kept.
    func send(_ data: Data) async throws
    /// Takes up the mirrored session the system kept after the app ended (iOS 26) as the newest; false when none.
    func recover() async throws -> Bool
}

/// The HealthKit calls only the phone makes.
protocol PhoneHealthServices: Sendable {
    /// `startWatchApp(toHandle:)`. Returns, or throws `CancellationError`, as soon as its task is cancelled.
    func startWatchApp() async throws
    /// Writes a workout the phone logged alone, with `HKWorkoutBuilder`: no heart rate, no energy.
    func saveWorkout(_ metadata: [String: HealthMetadataValue], start: Date, end: Date) async throws -> FinishedWorkout
    /// The saved workout with `uuid`, with its statistics; nil when Health has none.
    func workout(uuid: UUID) async throws -> FinishedWorkout?
}
