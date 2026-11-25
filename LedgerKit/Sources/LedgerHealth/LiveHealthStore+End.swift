import Foundation
import LedgerDomain
import os

// The end of a session (F16 S2b): saved, discarded or taken up again after the app ended; and the channel's sends,
// over the watch's session or the phone's newest mirrored one (S3a); and the phone's own calls (S3b).

public extension LiveHealthStore {
    /// Stops the activity, and on `.stopped` ends the collection, adds the metadata, finishes the workout (the
    /// one write) and ends the session (R1 §3.1).
    func endSession(metadata: HealthWorkoutMetadata, at end: Date) async throws -> HealthWorkoutRecord {
        guard let driver = session?.driver else {
            throw HealthError.noActiveSession
        }
        session?.isRunning = false
        session?.retry?.cancel()
        driver.stopActivity(at: end)
        try await reach(.stopped)
        try await driver.endCollection(at: end)
        try await driver.addMetadata(metadata.healthKitEntries(brandName: brandName))
        let workout = try await driver.finishWorkout()
        driver.end()
        detach()
        logger.notice("Workout saved to Health")
        sink.yield(.ended(end))
        return HealthWorkoutRecord(workout)
    }

    /// Ends the session and discards the builder's workout: nothing is written.
    func discardSession() throws {
        guard let driver = session?.driver else {
            throw HealthError.noActiveSession
        }
        driver.end()
        driver.discardWorkout()
        detach()
        logger.notice("Workout session discarded")
        sink.yield(.ended(now()))
    }

    /// Takes up the session HealthKit kept running after the app ended: on the watch, its builder, data source and
    /// delegates attached again (`handleActiveWorkoutRecovery()`); on the phone, the mirrored session, kept as the
    /// newest (`shouldHandleActiveWorkoutRecovery`).
    func recoverActiveSession() async throws -> Bool {
        if let mirror {
            guard try await mirror.recover() else {
                return false
            }
            logger.notice("Mirrored workout session recovered")
            sink.yield(.recovered)
            return true
        }
        guard session == nil, let driver = try await provider.recoverSession(), session == nil else {
            return false
        }
        attach(driver, state: .running, isRunning: true)
        logger.notice("Workout session recovered")
        sink.yield(.recovered)
        return true
    }

    /// Sends `data` over the watch's session to its mirror, or over the phone's newest mirrored session to the
    /// watch; `noActiveSession` when there is neither.
    func send(_ data: Data) async throws {
        if let driver = session?.driver {
            try await driver.send(data)
        } else if let mirror {
            try await mirror.send(data)
        } else {
            throw HealthError.noActiveSession
        }
    }
}

extension LiveHealthStore {
    /// Where the store's three streams are fed.
    struct Sinks {
        let events: AsyncStream<HealthSessionEvent>.Continuation
        let connection: AsyncStream<Bool>.Continuation
        let incoming: AsyncStream<[Data]>.Continuation
    }

    /// The phone's mirror, as the store reports it: each start as `.mirrorConnected` and `connection` true, then
    /// `onMirrorStart`; each drop as `.mirrorDisconnected` and false; each batch on `incoming`. It reads the mirror
    /// for the store's life, without the store, so the store's initializer can start it.
    static func forward(
        _ mirrorEvents: AsyncStream<MirrorEvent>,
        to sinks: Sinks,
        onMirrorStart: @escaping @Sendable (WorkoutID?) async -> Void
    ) -> Task<Void, Never> {
        Task {
            for await event in mirrorEvents {
                switch event {
                case .connected:
                    sinks.connection.yield(true)
                    sinks.events.yield(.mirrorConnected)
                    await onMirrorStart(nil)
                case .disconnected:
                    sinks.connection.yield(false)
                    sinks.events.yield(.mirrorDisconnected)
                case let .received(batch):
                    sinks.incoming.yield(batch)
                }
            }
        }
    }
}

extension LiveHealthStore {
    /// `operation`'s answer, or nil past `timeout` on the store's clock, when it is cancelled: it must return
    /// then (`WorkoutSessionDriver.startMirroring()`, `PhoneHealthServices.startWatchApp()`).
    func answer(
        within timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async -> Result<Void, HealthError>? {
        let clock = clock
        return await withTaskGroup(of: Result<Void, HealthError>?.self) { group in
            group.addTask {
                do {
                    try await operation()
                    return .success(())
                } catch let error as HealthError {
                    return .failure(error)
                } catch {
                    return nil // cancelled: the timeout went first, and this answer is not read
                }
            }
            group.addTask {
                // Cancelled when the operation answers first; this answer is then not read.
                try? await clock.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

// The phone's calls (F16 S3). On the watch they throw `unavailable`: it never asks itself to start, saves only by
// ending its session, and has no caller for records.

public extension LiveHealthStore {
    /// Opens the watch app with a session running; `watchAppUnavailable` when it fails or has not answered in
    /// `watchStartTimeout` (criterion 8). Authorization failures are reported as themselves.
    func requestWatchStart() async throws {
        guard let phone else {
            throw HealthError.unavailable
        }
        switch await answer(within: Self.watchStartTimeout, { try await phone.startWatchApp() }) {
        case .success:
            logger.notice("Asked the watch to start a workout")
        case let .failure(error) where error == .notAuthorized || error == .unavailable:
            throw error
        case .failure, nil:
            logger.notice("The watch app did not start a workout")
            throw HealthError.watchAppUnavailable
        }
    }

    /// Saves a workout the phone logged alone, without heart rate or energy. Refused with `watchSavesThisWorkout`
    /// when a watch took part: its session writes that workout (architecture §9).
    func saveWorkout(metadata: HealthWorkoutMetadata, start: Date, end: Date) async throws -> HealthWorkoutRecord {
        guard let phone else {
            throw HealthError.unavailable
        }
        try await requireAuthorized()
        guard await !watchTookPart(metadata.workoutID) else {
            throw HealthError.watchSavesThisWorkout
        }
        let workout = try await phone.saveWorkout(
            metadata.healthKitEntries(brandName: brandName),
            start: start,
            end: end
        )
        logger.notice("Phone-only workout saved to Health")
        return HealthWorkoutRecord(
            healthKitUUID: workout.uuid,
            start: workout.start,
            end: workout.end,
            avgHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKcal: nil
        )
    }

    func workoutRecord(healthKitUUID: UUID) async throws -> HealthWorkoutRecord? {
        guard let phone else {
            throw HealthError.unavailable
        }
        return try await phone.workout(uuid: healthKitUUID).map(HealthWorkoutRecord.init)
    }
}

private extension HealthWorkoutRecord {
    init(_ workout: FinishedWorkout) {
        self.init(
            healthKitUUID: workout.uuid,
            start: workout.start,
            end: workout.end,
            avgHeartRate: workout.avgHeartRate,
            maxHeartRate: workout.maxHeartRate,
            activeEnergyKcal: workout.activeEnergyKcal
        )
    }
}
