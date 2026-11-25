import Foundation
import LedgerDomain
@testable import LedgerHealth
import Synchronization

/// The phone's own HealthKit calls, scripted: how `startWatchApp()` answers, and what saving and reading find.
final class ScriptedPhone: PhoneHealthServices {
    enum WatchStart: Sendable {
        case opens
        case fails(HealthError)
        /// Never answers: returns only when cancelled, as the seam promises.
        case hangs
    }

    /// One `saveWorkout` call.
    struct Save {
        let metadata: [String: HealthMetadataValue]
        let start: Date
        let end: Date
    }

    private let watchStart: WatchStart
    private let saved = Mutex<[Save]>([])

    init(watchStart: WatchStart = .opens) {
        self.watchStart = watchStart
    }

    var saves: [Save] {
        saved.withLock { $0 }
    }

    func startWatchApp() async throws {
        switch watchStart {
        case .opens:
            return
        case let .fails(error):
            throw error
        case .hangs:
            let (never, keep) = AsyncStream<Void>.makeStream()
            for await _ in never {}
            withExtendedLifetime(keep) {}
            throw CancellationError()
        }
    }

    /// Answers with `ScriptedSession.workout`'s id and statistics, which the store must not pass on.
    func saveWorkout(_ metadata: [String: HealthMetadataValue], start: Date, end: Date) -> FinishedWorkout {
        saved.withLock { $0.append(Save(metadata: metadata, start: start, end: end)) }
        let workout = ScriptedSession.workout
        return FinishedWorkout(
            uuid: workout.uuid,
            start: start,
            end: end,
            avgHeartRate: workout.avgHeartRate,
            maxHeartRate: workout.maxHeartRate,
            activeEnergyKcal: workout.activeEnergyKcal
        )
    }

    /// Health holds `ScriptedSession.workout` only.
    func workout(uuid: UUID) -> FinishedWorkout? {
        uuid == ScriptedSession.workout.uuid ? ScriptedSession.workout : nil
    }
}
