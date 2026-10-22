import Foundation
import LedgerDomain

/// `statsQueries`' live value until the composition root binds `GRDBStatsQueries` (F07 S2): every query logs at
/// fault level and throws `LedgerDependencyError.unimplemented(key:)`.
struct UnimplementedStatsQueries: StatsQueries {
    let stub = Unimplemented(key: "statsQueries")

    func lastPerformance(exerciseID _: ExerciseID) async throws -> LastPerformance? {
        throw stub.failure()
    }

    func bestSet(exerciseID _: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        throw stub.failure()
    }

    func bestSets() async throws -> [ExerciseID: BestSet] {
        throw stub.failure()
    }

    func bestE1RM(exerciseID _: ExerciseID) async throws -> Weight? {
        throw stub.failure()
    }

    func e1RMByWeek(
        exerciseID _: ExerciseID,
        lastWeeks _: Int,
        calendar _: WeekCalendar
    ) async throws -> [WeekKey: Weight] {
        throw stub.failure()
    }

    func weeklyVolume(in _: Range<Date>) async throws -> Volume {
        throw stub.failure()
    }

    func sessionsCompleted(in _: Range<Date>) async throws -> Int {
        throw stub.failure()
    }

    func sessionCount(exerciseID _: ExerciseID) async throws -> Int {
        throw stub.failure()
    }

    func personalRecords(exerciseID _: ExerciseID) async throws -> [PersonalRecord] {
        throw stub.failure()
    }

    func bests(before _: WorkoutState, for _: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        throw stub.failure()
    }

    func recentlyLogged(limit _: Int) async throws -> [ExerciseID] {
        throw stub.failure()
    }

    func exerciseSessions(exerciseID _: ExerciseID) async throws -> [ExerciseSession] {
        throw stub.failure()
    }
}
