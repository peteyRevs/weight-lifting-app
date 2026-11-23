import Foundation
import LedgerDomain
import os

// The end of a session (F16 S2b): saved, discarded or taken up again after the app ended; and the channel's sends.

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
        return HealthWorkoutRecord(
            healthKitUUID: workout.uuid,
            start: workout.start,
            end: workout.end,
            avgHeartRate: workout.avgHeartRate,
            maxHeartRate: workout.maxHeartRate,
            activeEnergyKcal: workout.activeEnergyKcal
        )
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

    /// Takes up the session HealthKit kept running after the app ended, its builder, data source and delegates
    /// attached again (`handleActiveWorkoutRecovery()`).
    func recoverActiveSession() async throws -> Bool {
        guard session == nil, let driver = try await provider.recoverSession(), session == nil else {
            return false
        }
        attach(driver, state: .running, isRunning: true)
        logger.notice("Workout session recovered")
        sink.yield(.recovered)
        return true
    }

    /// Sends `data` over the session to its mirror; `noActiveSession` when there is no session.
    func send(_ data: Data) async throws {
        guard let driver = session?.driver else {
            throw HealthError.noActiveSession
        }
        try await driver.send(data)
    }
}

// The phone's calls, which F16 S3 implements on iOS. On the watch they stay unavailable: it never asks itself to
// start, saves only by ending its session, and has no caller for records.

public extension LiveHealthStore {
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
