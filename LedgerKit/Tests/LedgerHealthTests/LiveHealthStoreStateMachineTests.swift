import Foundation
import LedgerDomain
import LedgerFakes
@testable import LedgerHealth
import Testing

/// `LiveHealthStore`'s state machine over a scripted session (F16 S2a; criteria 3 and 4 as far as a script plays
/// them): no HealthKit call, and time moves only on `ManualClock`.
@Suite("Live health store state machine", .timeLimit(.minutes(1)))
struct LiveHealthStoreStateMachineTests {
    static let workout = WorkoutID(Fixtures.uuid(1))
    static let start = Fixtures.now

    /// A store whose mirroring timeout and retries wait on `clock`, never on the wall clock.
    static func store(_ provider: ScriptedProvider, clock: ManualClock = ManualClock()) -> LiveHealthStore {
        LiveHealthStore(provider: provider, clock: clock)
    }

    static func events(_ count: Int, of store: LiveHealthStore) async -> [HealthSessionEvent] {
        await HealthStoreContractTests.next(count, of: store.events)
    }

    /// Starts `store`'s session, playing `.prepared` only once `prepare()` has been called.
    static func start(_ store: LiveHealthStore, on session: ScriptedSession) async throws {
        let starting = Task { try await store.startSession(workoutID: workout, at: start) }
        await session.wait(for: "prepare")
        session.play(.state(.prepared, start))
        try await starting.value
    }
}

// Criterion 3: prepared, then mirroring under its timeout, then running; a dropped mirror is retried.

extension LiveHealthStoreStateMachineTests {
    @Test("The start waits for .prepared before it mirrors, then starts the activity and the collection")
    func startSession_waitsForPreparedBeforeMirroring() async throws {
        let session = ScriptedSession(autoplay: false)
        let store = Self.store(ScriptedProvider(session: session))
        try await Self.start(store, on: session)
        #expect(session.log == ["prepare", "→prepared", "startMirroring", "startActivity", "beginCollection"])
        #expect(await Self.events(3, of: store) == [.prepared, .mirrorConnected, .running(since: Self.start)])
        #expect(await HealthStoreContractTests.next(1, of: store.remoteChannel.connection) == [true])
    }

    @Test("Mirroring that does not answer in 10 s is reported, and the session runs without it")
    func mirroringTimeoutIsNonFatal() async throws {
        let clock = ManualClock()
        let session = ScriptedSession(mirroring: [.hangs])
        let store = Self.store(ScriptedProvider(session: session), clock: clock)
        let starting = Task { try await store.startSession(workoutID: Self.workout, at: Self.start) }
        #expect(await clock.nextSleep(skipping: .zero) == .seconds(10))
        clock.advance(by: .seconds(10))
        try await starting.value
        #expect(await Self.events(3, of: store) == [
            .prepared, .failed(.mirroringTimedOut), .running(since: Self.start)
        ])
        #expect(session.log.suffix(2) == ["startActivity", "beginCollection"])
    }

    @Test("Mirroring that fails is reported as its error, and the session runs without it")
    func mirroringFailureIsNonFatal() async throws {
        let session = ScriptedSession(mirroring: [.fails])
        let store = Self.store(ScriptedProvider(session: session))
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        #expect(await Self.events(3, of: store) == [
            .prepared, .failed(.underlying(code: 100)), .running(since: Self.start)
        ])
    }

    @Test("A dropped mirror is retried after 2, 4 and 8 s while the session runs")
    func mirroringRetries_backoff2_4_8() async throws {
        let clock = ManualClock()
        let session = ScriptedSession(mirroring: [.connects, .fails, .fails, .connects])
        let store = Self.store(ScriptedProvider(session: session), clock: clock)
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        #expect(await Self.events(3, of: store).last == .running(since: Self.start))
        session.play(.mirrorDisconnected)
        for wait in [Duration.seconds(2), .seconds(4), .seconds(8)] {
            #expect(await clock.nextSleep(skipping: LiveHealthStore.mirroringTimeout) == wait)
            clock.advance(by: wait)
        }
        #expect(await Self.events(2, of: store) == [.mirrorDisconnected, .mirrorConnected])
        #expect(session.log.count(where: { $0 == "startMirroring" }) == 4)
        #expect(await HealthStoreContractTests.next(3, of: store.remoteChannel.connection) == [true, false, true])
    }

    @Test("A start is refused without authorization, and while a session runs")
    func startSession_refusals() async throws {
        for (status, error) in [
            (HealthAuthorization.denied, HealthError.notAuthorized),
            (.unavailable, .unavailable)
        ] {
            let refused = Self.store(ScriptedProvider(status: status))
            await #expect(throws: error) { try await refused.startSession(workoutID: Self.workout, at: Self.start) }
        }
        let store = Self.store(ScriptedProvider())
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        await #expect(throws: HealthError.sessionAlreadyRunning) {
            try await store.startSession(workoutID: Self.workout, at: Self.start)
        }
    }

    @Test("A failure before .prepared is reported, fails the start, and ends that session writing nothing")
    func failureBeforePrepared_failsTheStart() async throws {
        let session = ScriptedSession(autoplay: false)
        let store = Self.store(ScriptedProvider(session: session))
        let starting = Task { try await store.startSession(workoutID: Self.workout, at: Self.start) }
        await session.wait(for: "prepare")
        session.play(.failed(.underlying(code: 3)))
        await #expect(throws: HealthError.underlying(code: 3)) { try await starting.value }
        #expect(await Self.events(1, of: store) == [.failed(.underlying(code: 3))])
        #expect(session.log == ["prepare", "→failed underlying(code: 3)", "end", "discardWorkout"])
    }
}

// Criterion 4, authorization and what later slices implement.

extension LiveHealthStoreStateMachineTests {
    @Test("Heart rate arrives in order, on every stream")
    func heartRate_inOrder() async throws {
        let session = ScriptedSession()
        let store = Self.store(ScriptedProvider(session: session))
        try await store.startSession(workoutID: Self.workout, at: Self.start)
        let first = await store.heartRate()
        let second = await store.heartRate()
        let samples = HealthStoreContractTests.samples([96, 101, 99])
        samples.forEach { session.play(.heartRate($0)) }
        #expect(await HealthStoreContractTests.next(3, of: first) == samples)
        #expect(await HealthStoreContractTests.next(3, of: second) == samples)
    }

    @Test("Authorization is the provider's; the end, recovery, the channel and the phone's calls are not yet")
    func authorization_andLaterSlices() async throws {
        let store = Self.store(ScriptedProvider(status: .denied))
        #expect(await store.authorization() == .denied)
        #expect(try await store.requestAuthorization() == .denied)
        let metadata = HealthStoreContractTests.metadata
        await #expect(throws: HealthError.unavailable) { try await store.endSession(
            metadata: metadata,
            at: Self.start
        ) }
        await #expect(throws: HealthError.unavailable) { try await store.discardSession() }
        await #expect(throws: HealthError.unavailable) { try await store.recoverActiveSession() }
        await #expect(throws: HealthError.unavailable) { try await store.remoteChannel.send(Data([1])) }
        await #expect(throws: HealthError.unavailable) { try await store.requestWatchStart() }
        await #expect(throws: HealthError.unavailable) {
            try await store.saveWorkout(metadata: metadata, start: Self.start, end: Self.start)
        }
        await #expect(throws: HealthError.unavailable) {
            try await store.workoutRecord(healthKitUUID: Fixtures.uuid(2))
        }
    }
}
