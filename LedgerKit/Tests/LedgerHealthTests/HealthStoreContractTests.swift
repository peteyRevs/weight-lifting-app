import Foundation
import LedgerDomain
import LedgerFakes
import Testing

/// What every `HealthStore` promises (F16 criterion 13), held against `FakeHealthStore`: criteria 3, 4, 6, 7, 9
/// and 12 as far as a script can play them. `LiveHealthStore` joins the clauses a device can drive in F16 S2/S3,
/// on the device lane only (testing-strategy §2.4).
@Suite("Health store contract", .timeLimit(.minutes(1)))
struct HealthStoreContractTests {
    static let workout = WorkoutID(Fixtures.uuid(1))
    static let start = Fixtures.now
    static let end = Fixtures.now.addingTimeInterval(3600)
    static let metadata = HealthWorkoutMetadata(
        workoutID: workout,
        programName: "Strength",
        dayName: "Day A",
        totalVolume: .kilograms(4200),
        doneSets: 15
    )

    /// The next `count` values of `stream`.
    static func next<Element: Sendable>(_ count: Int, of stream: AsyncStream<Element>) async -> [Element] {
        var iterator = stream.makeAsyncIterator()
        var values: [Element] = []
        while values.count < count, let value = await iterator.next() {
            values.append(value)
        }
        return values
    }

    static func samples(_ beats: [Int]) -> [HeartRateSample] {
        beats.enumerated().map { HeartRateSample(bpm: $1, date: start.addingTimeInterval(Double($0 * 5))) }
    }
}

// Authorization, then criteria 3, 4, 5 (the fake's half) and 6: start, heart rate, end and save, discard.

extension HealthStoreContractTests {
    @Test("Authorization is asked once and the answer stands; without HealthKit, asking throws unavailable")
    func authorization_askedOnce() async throws {
        let store = FakeHealthStore(authorization: .notDetermined, grant: .denied)
        #expect(await store.authorization() == .notDetermined)
        #expect(try await store.requestAuthorization() == .denied)
        #expect(try await store.requestAuthorization() == .denied)
        #expect(await store.authorization() == .denied)
        let absent = FakeHealthStore(authorization: .unavailable)
        await #expect(throws: HealthError.unavailable) { try await absent.requestAuthorization() }
    }

    @Test(
        "A session is prepared, then mirrored or told mirroring timed out, then running",
        arguments: [
            (FakeHealthStore.Mirroring.connects, HealthSessionEvent.mirrorConnected),
            (.timesOut, .failed(.mirroringTimedOut))
        ]
    )
    func startSession_preparedThenMirroringThenRunning(
        mirroring: FakeHealthStore.Mirroring,
        outcome: HealthSessionEvent
    ) async throws {
        let store = FakeHealthStore(authorization: .authorized, mirroring: mirroring)
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        #expect(await Self.next(3, of: store.events) == [.prepared, outcome, .running(since: Self.start)])
        #expect(await store.activeSession == FakeHealthStore.Session(workoutID: Self.workout, start: Self.start))
    }

    @Test("A start is refused without authorization, and while a session runs")
    func startSession_refusals() async throws {
        let undecided = FakeHealthStore(authorization: .notDetermined)
        await #expect(throws: HealthError.notAuthorized) {
            try await undecided.startSession(workoutID: Self.workout, at: Self.start)
        }
        let store = FakeHealthStore(authorization: .authorized)
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        await #expect(throws: HealthError.sessionAlreadyRunning) {
            try await store.startSession(workoutID: WorkoutID(Fixtures.uuid(2)), at: Self.end)
        }
        #expect(await store.activeSession?.workoutID == Self.workout)
    }

    @Test("Heart rate arrives in order, on every stream")
    func heartRate_inOrder() async throws {
        let store = FakeHealthStore(authorization: .authorized)
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        let first = await store.heartRate()
        let second = await store.heartRate()
        let scripted = Self.samples([88, 97, 104])
        await store.simulateHeartRate(scripted)
        #expect(await Self.next(3, of: first) == scripted)
        #expect(await Self.next(3, of: second) == scripted)
    }

    @Test("Ending saves one workout with the session's span and heart rate, findable by its UUID")
    func endSession_savesTheRecord() async throws {
        let store = FakeHealthStore(authorization: .authorized, activeEnergyKcal: 210)
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        await store.simulateHeartRate(Self.samples([90, 120, 151]))
        let record = try await store.endSession(metadata: Self.metadata, at: Self.end)
        #expect(record.start == Self.start && record.end == Self.end)
        #expect(record.avgHeartRate == 120 && record.maxHeartRate == 151 && record.activeEnergyKcal == 210)
        #expect(try await store.workoutRecord(healthKitUUID: record.healthKitUUID) == record)
        #expect(try await store.workoutRecord(healthKitUUID: Fixtures.uuid(99)) == nil)
        #expect(await store.savedMetadata == [Self.metadata])
        #expect(await store.activeSession == nil)
        #expect(await Self.next(4, of: store.events).last == .ended(Self.end))
        await #expect(throws: HealthError.noActiveSession) {
            try await store.endSession(metadata: Self.metadata, at: Self.end)
        }
    }

    @Test("A discarded session ends and writes nothing")
    func discardSession_writesNothing() async throws {
        let store = FakeHealthStore(authorization: .authorized)
        await #expect(throws: HealthError.noActiveSession) { try await store.discardSession() }
        #expect(await !store.discarded)
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        try await store.discardSession()
        #expect(await store.discarded)
        #expect(await store.saved.isEmpty)
        #expect(await store.activeSession == nil)
        #expect(await Self.next(4, of: store.events).last == .ended(Fixtures.now))
    }
}

// Criteria 7, 9 and 12: mirrored sessions, another workout taking over, a phone-only save; recovery and the phone's
// start request.

extension HealthStoreContractTests {
    @Test("Each mirrored session is kept, and the channel rebinds to the newest")
    func mirror_retainsEverySession_rebindsToNewest() async throws {
        let store = FakeHealthStore(authorization: .authorized)
        await store.simulateMirrorStarted()
        try await store.remoteChannel.send(Data([1]))
        await store.simulateMirrorStarted()
        try await store.remoteChannel.send(Data([2]))
        #expect(await store.mirroredSessionCount == 2)
        #expect(await store.sent.map(\.session) == [1, 2])
        #expect(await store.boundSession == 2)
        #expect(await Self.next(2, of: store.events) == [.mirrorConnected, .mirrorConnected])
        #expect(await Self.next(2, of: store.remoteChannel.connection) == [true, true])
    }

    @Test("A disconnect is reported, and nothing is sent until a session reconnects")
    func mirror_disconnect() async throws {
        let store = FakeHealthStore(authorization: .authorized)
        await store.simulateMirrorStarted()
        await store.simulateMirrorDisconnected()
        await #expect(throws: HealthError.noActiveSession) { try await store.remoteChannel.send(Data([1])) }
        #expect(await Self.next(2, of: store.events) == [.mirrorConnected, .mirrorDisconnected])
        #expect(await Self.next(2, of: store.remoteChannel.connection) == [true, false])
    }

    @Test("What the other device sends arrives in batches, in order")
    func channel_incomingInOrder() async {
        let store = FakeHealthStore(authorization: .authorized)
        await store.simulateIncoming([Data([1]), Data([2])])
        await store.simulateIncoming([Data([3])])
        #expect(await Self.next(2, of: store.remoteChannel.incoming) == [[Data([1]), Data([2])], [Data([3])]])
    }

    @Test("Another app's workout ends ours with its own event, and nothing is saved")
    func anotherWorkoutSessionStarted_endsWithoutSaving() async throws {
        let store = FakeHealthStore(authorization: .authorized)
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        await store.simulateAnotherWorkoutSessionStarted()
        #expect(await Self.next(4, of: store.events).last == .anotherWorkoutSessionStarted)
        #expect(await store.saved.isEmpty)
        await #expect(throws: HealthError.noActiveSession) {
            try await store.endSession(metadata: Self.metadata, at: Self.end)
        }
    }

    @Test("Recovery takes up the session the system ended, once, and it ends as any other")
    func recoverActiveSession() async throws {
        let session = FakeHealthStore.Session(workoutID: Self.workout, start: Self.start)
        let store = FakeHealthStore(authorization: .authorized, recoverable: session)
        #expect(try await store.recoverActiveSession())
        #expect(try await !store.recoverActiveSession())
        #expect(await Self.next(1, of: store.events) == [.recovered])
        #expect(try await store.endSession(metadata: Self.metadata, at: Self.end).start == Self.start)
        #expect(try await !FakeHealthStore(authorization: .authorized).recoverActiveSession())
    }

    @Test("Asking the watch to start throws watchAppUnavailable when the watch app is missing")
    func requestWatchStart() async throws {
        try await FakeHealthStore(authorization: .authorized).requestWatchStart()
        let absent = FakeHealthStore(authorization: .authorized, watchAppInstalled: false)
        await #expect(throws: HealthError.watchAppUnavailable) { try await absent.requestWatchStart() }
        #expect(await absent.watchStartRequests == 1)
    }

    @Test("A phone-only save writes one workout without heart rate; it needs authorization")
    func saveWorkout_phoneOnly_hasNoHeartRate() async throws {
        let store = FakeHealthStore(authorization: .authorized)
        let record = try await store.saveWorkout(metadata: Self.metadata, start: Self.start, end: Self.end)
        #expect(record.avgHeartRate == nil && record.maxHeartRate == nil && record.activeEnergyKcal == nil)
        #expect(await store.saved == [record])
        #expect(try await store.workoutRecord(healthKitUUID: record.healthKitUUID) == record)
        let denied = FakeHealthStore(authorization: .denied)
        await #expect(throws: HealthError.notAuthorized) {
            try await denied.saveWorkout(metadata: Self.metadata, start: Self.start, end: Self.end)
        }
    }
}
