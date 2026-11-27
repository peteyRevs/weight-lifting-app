import Foundation
import LedgerDomain

/// What the watch's Health session fills in the store (F18 S3), and the summary's records: in a file of its own for
/// the store's length.
extension WatchWorkoutStore {
    var heartRate: HeartRateSample? {
        healthState.heartRate
    }

    var health: HealthAuthorization {
        healthState.authorization
    }

    /// What Health saved for the workout on screen: the summary's AVG BPM (criterion 11).
    var healthRecord: HealthWorkoutRecord? {
        healthState.saved.flatMap { $0.workout == workout?.id ? $0.record : nil }
    }

    /// Whether another app's workout took the live workout's session over: "Apple Workout took over · logging
    /// continues" (spec §9), the root's banner.
    var isHealthTakenOver: Bool {
        live.map { $0.id == healthState.takenOver } ?? false
    }

    /// The banner over the live workout's screens: the takeover's line while it holds, else none.
    var banner: String? {
        isHealthTakenOver ? WatchWorkoutCopy.healthTakenOver : nil
    }

    /// The Health session's state, for as long as the root's task runs.
    func followHealth() async {
        guard let healthSession else {
            return
        }
        for await state in await healthSession.states() {
            healthState = state
        }
    }

    /// Judges each finished workout shown against the bests before it, for the summary's NEW PR (criterion 11). A
    /// read that fails is logged and the summary shows none; one answered after another workout replaced it is
    /// dropped.
    func followRecords(_ finished: AsyncStream<WorkoutState>) async {
        for await ended in finished {
            do {
                let bests = try await stats.bests(before: ended, for: Set(ended.exercises.map(\.exerciseID)))
                if workout?.id == ended.id {
                    records = PersonalRecords.detect(workout: ended, against: bests, now: ended.startedAt)
                }
            } catch {
                logger.log.error("The bests could not be read: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
