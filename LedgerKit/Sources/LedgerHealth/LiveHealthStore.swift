import Foundation
import LedgerDomain
import os

/// `HealthStore` over HealthKit (F16; architecture §9). The state machine is the same on every platform and
/// drives a `WorkoutSessionProvider`: in tests, a script; on the watch, from F16 S2b, HealthKit's session. S2a
/// starts a session, mirrors it and streams its heart rate; until S2b (the HealthKit provider, the end, a
/// discard, recovery) and S3 (the phone's calls) land, the other calls throw `HealthError.unavailable`, and no
/// composition binds it.
///
/// Each delegate callback reaches the actor through the session's `callbacks` stream, which one listener task
/// per session reads in order; the task is the session's, and is cancelled when the session ends. It is the
/// store's own `remoteChannel`, whose `connection` follows the mirror.
public actor LiveHealthStore: HealthStore, RemoteSessionChannel {
    /// How long mirroring to the phone may take before the session runs without it (R1 §2.5 gotcha 5).
    static let mirroringTimeout = Duration.seconds(10)
    /// The waits before each retry of a mirror that dropped while the session runs.
    static let mirroringBackoff: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]

    public nonisolated let events: AsyncStream<HealthSessionEvent>
    public nonisolated let connection: AsyncStream<Bool>
    public nonisolated let incoming: AsyncStream<[Data]>
    public nonisolated var remoteChannel: any RemoteSessionChannel {
        self
    }

    private let provider: any WorkoutSessionProvider
    private let clock: any Clock<Duration>
    private let sink: AsyncStream<HealthSessionEvent>.Continuation
    private let connectionSink: AsyncStream<Bool>.Continuation
    /// Held so that `incoming` stays open; S2b yields the phone's batches into it.
    private let incomingSink: AsyncStream<[Data]>.Continuation
    private let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "health")
    private var session: Session?
    private var sessionsAttached = 0
    private var waiter: Waiter?
    private var heartRateSubscribers: [AsyncStream<HeartRateSample>.Continuation] = []

    /// The session HealthKit holds for the store.
    private struct Session {
        /// Which attached session this is, so a callback or task of an earlier one changes nothing.
        let number: Int
        let driver: any WorkoutSessionDriver
        let listener: Task<Void, Never>
        var state: WorkoutSessionState
        /// Started and not yet ending: a dropped mirror is retried only then.
        var isRunning: Bool
        var retry: Task<Void, Never>?
    }

    /// A call waiting for the session to reach `state`.
    private struct Waiter {
        let state: WorkoutSessionState
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// What one try at mirroring came to.
    enum Mirroring: Equatable {
        case connected, timedOut, failed(HealthError)
    }

    /// `clock` times mirroring and its retries.
    init(provider: any WorkoutSessionProvider, clock: any Clock<Duration> = ContinuousClock()) {
        self.provider = provider
        self.clock = clock
        (events, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (connection, connectionSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (incoming, incomingSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    deinit {
        session?.listener.cancel()
        session?.retry?.cancel()
    }

    public func authorization() async -> HealthAuthorization {
        await provider.authorization()
    }

    public func requestAuthorization() async throws -> HealthAuthorization {
        try await provider.requestAuthorization()
    }

    /// Prepares, waits for `.prepared`, mirrors (non-fatal past `mirroringTimeout`), then starts the activity
    /// and the builder's collection (ADR-005; R1 §2.5 gotchas 1, 3 and 5). A failure before `.running` ends
    /// the session and writes nothing.
    public func startSession(workoutID _: WorkoutID, at start: Date) async throws {
        try await requireAuthorized()
        guard session == nil else {
            throw HealthError.sessionAlreadyRunning
        }
        let driver = try provider.makeSession()
        let number = attach(driver)
        do {
            driver.prepare()
            try await reach(.prepared)
            sink.yield(.prepared)
            switch await mirror(driver) {
            case .connected: announceMirrorConnected()
            case .timedOut: sink.yield(.failed(.mirroringTimedOut))
            case let .failed(error): sink.yield(.failed(error))
            }
            driver.startActivity(at: start)
            try await driver.beginCollection(at: start)
        } catch {
            if session?.number == number {
                driver.end()
                driver.discardWorkout()
                detach()
            }
            throw error
        }
        session?.isRunning = true
        logger.notice("Workout session running")
        sink.yield(.running(since: start))
    }

    public func heartRate() -> AsyncStream<HeartRateSample> {
        let (stream, continuation) = AsyncStream<HeartRateSample>.makeStream(bufferingPolicy: .unbounded)
        heartRateSubscribers.append(continuation)
        return stream
    }
}

// What F16 S2b (the end, a discard, recovery, the channel's data) and S3 (the phone's calls) implement.

public extension LiveHealthStore {
    func endSession(metadata _: HealthWorkoutMetadata, at _: Date) throws -> HealthWorkoutRecord {
        throw HealthError.unavailable
    }

    func discardSession() throws {
        throw HealthError.unavailable
    }

    func recoverActiveSession() throws -> Bool {
        throw HealthError.unavailable
    }

    func send(_: Data) throws {
        throw HealthError.unavailable
    }

    func requestWatchStart() throws {
        throw HealthError.unavailable
    }

    func saveWorkout(metadata _: HealthWorkoutMetadata, start _: Date, end _: Date) throws -> HealthWorkoutRecord {
        throw HealthError.unavailable
    }

    func workoutRecord(healthKitUUID _: UUID) throws -> HealthWorkoutRecord? {
        throw HealthError.unavailable
    }
}

// The session's life: its listener, its callbacks, mirroring and its retries.

private extension LiveHealthStore {
    func requireAuthorized() async throws {
        switch await provider.authorization() {
        case .authorized: return
        case .unavailable: throw HealthError.unavailable
        case .notDetermined, .denied: throw HealthError.notAuthorized
        }
    }

    func attach(_ driver: any WorkoutSessionDriver) -> Int {
        sessionsAttached += 1
        let number = sessionsAttached
        let callbacks = driver.callbacks
        let listener = Task { [weak self] in
            for await callback in callbacks {
                await self?.handle(callback, session: number)
            }
        }
        session = Session(number: number, driver: driver, listener: listener, state: .notStarted, isRunning: false)
        return number
    }

    /// Forgets the session; a call still waiting on it throws `noActiveSession`.
    func detach() {
        session?.listener.cancel()
        session?.retry?.cancel()
        session = nil
        waiter.take()?.continuation.resume(throwing: HealthError.noActiveSession)
    }

    /// Returns once the session reaches `state`; throws what ends it first.
    func reach(_ state: WorkoutSessionState) async throws {
        guard let session else {
            throw HealthError.noActiveSession
        }
        guard session.state != state else {
            return
        }
        try await withCheckedThrowingContinuation { waiter = Waiter(state: state, continuation: $0) }
    }

    func handle(_ callback: WorkoutSessionCallback, session number: Int) {
        guard session?.number == number else {
            return
        }
        switch callback {
        case let .state(state, _):
            session?.state = state
            if waiter?.state == state {
                waiter.take()?.continuation.resume()
            }
        case let .failed(error):
            logger.error("Workout session failed: \(String(describing: error), privacy: .public)")
            waiter.take()?.continuation.resume(throwing: error)
            sink.yield(.failed(error))
        case let .heartRate(sample):
            heartRateSubscribers.removeAll { continuation in
                if case .terminated = continuation.yield(sample) {
                    true
                } else {
                    false
                }
            }
        case .mirrorDisconnected:
            logger.notice("Mirroring to the phone dropped")
            connectionSink.yield(false)
            sink.yield(.mirrorDisconnected)
            if session?.isRunning == true, session?.retry == nil {
                session?.retry = Task { [weak self] in await self?.retryMirroring(session: number) }
            }
        }
    }

    /// Mirrors again after each of `mirroringBackoff`'s waits until it connects; gives up after the last.
    func retryMirroring(session number: Int) async {
        for delay in Self.mirroringBackoff {
            // A cancelled wait means the session ended: there is nothing left to mirror.
            guard await (try? clock.sleep(for: delay)) != nil,
                  let driver = session?.driver, session?.number == number
            else {
                return
            }
            if await mirror(driver) == .connected, session?.number == number {
                announceMirrorConnected()
                session?.retry = nil
                return
            }
        }
        logger.notice("Mirroring to the phone was not restored")
        if session?.number == number {
            session?.retry = nil
        }
    }

    /// One try at `startMirroringToCompanionDevice()`, which may hang: past `mirroringTimeout` it is cancelled,
    /// and the driver promises to return when it is.
    func mirror(_ driver: any WorkoutSessionDriver) async -> Mirroring {
        let clock = clock
        return await withTaskGroup(of: Mirroring.self) { group in
            group.addTask {
                do {
                    try await driver.startMirroring()
                    return .connected
                } catch let error as HealthError {
                    return .failed(error)
                } catch {
                    return .timedOut // cancelled: the timeout went first, and this answer is not read
                }
            }
            group.addTask {
                // Cancelled when mirroring answers first; this answer is then not read.
                try? await clock.sleep(for: Self.mirroringTimeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    func announceMirrorConnected() {
        logger.notice("Mirroring to the phone")
        connectionSink.yield(true)
        sink.yield(.mirrorConnected)
    }
}
