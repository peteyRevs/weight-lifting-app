import Foundation
import LedgerDomain
import LedgerTestSupport

/// `FakeHealthStore` behind a gate: `startSession` reports that it was called, then waits until the test opens the
/// gate before the fake starts the session; `endSession` and `discardSession` report each call. Everything else is
/// the fake's.
actor GatedHealthStore: HealthStore {
    enum Call: Equatable, Sendable {
        case startEntered, ended, discarded
    }

    let fake: FakeHealthStore
    nonisolated let calls: AsyncStream<Call>
    private let report: AsyncStream<Call>.Continuation
    private var gate: CheckedContinuation<Void, Never>?
    private var isOpen = false

    init(_ fake: FakeHealthStore) {
        self.fake = fake
        (calls, report) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func open() {
        isOpen = true
        gate.take()?.resume()
    }

    nonisolated var events: AsyncStream<HealthSessionEvent> {
        fake.events
    }

    nonisolated var remoteChannel: any RemoteSessionChannel {
        fake.remoteChannel
    }

    func startSession(workoutID: WorkoutID, at start: Date) async throws {
        report.yield(.startEntered)
        if !isOpen {
            await withCheckedContinuation { gate = $0 }
        }
        try await fake.startSession(workoutID: workoutID, at: start)
    }

    func endSession(metadata: HealthWorkoutMetadata, at end: Date) async throws -> HealthWorkoutRecord {
        let record = try await fake.endSession(metadata: metadata, at: end)
        report.yield(.ended)
        return record
    }

    func discardSession() async throws {
        try await fake.discardSession()
        report.yield(.discarded)
    }

    func authorization() async -> HealthAuthorization {
        await fake.authorization()
    }

    func requestAuthorization() async throws -> HealthAuthorization {
        try await fake.requestAuthorization()
    }

    func heartRate() async -> AsyncStream<HeartRateSample> {
        await fake.heartRate()
    }

    func recoverActiveSession() async throws -> Bool {
        await fake.recoverActiveSession()
    }

    nonisolated func noteStartRequestedByPhone() {
        fake.noteStartRequestedByPhone()
    }

    func requestWatchStart() async throws {
        try await fake.requestWatchStart()
    }

    func saveWorkout(metadata: HealthWorkoutMetadata, start: Date, end: Date) async throws -> HealthWorkoutRecord {
        try await fake.saveWorkout(metadata: metadata, start: start, end: end)
    }

    func workoutRecord(healthKitUUID: UUID) async throws -> HealthWorkoutRecord? {
        await fake.workoutRecord(healthKitUUID: healthKitUUID)
    }
}
