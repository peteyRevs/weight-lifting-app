@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport

extension WorkoutStore {
    /// F10 S7b: a save this cover made shows the receipt of `id` and keeps the cover up; this taps "Done", as
    /// the lifter does, after which the cover closes as saved. False, and nothing sent, when no receipt of
    /// `id` is on screen or the cover is already closing.
    func doneOnReceipt(of id: WorkoutID) -> Bool {
        guard saved?.id == id, exit == nil, case .receipt = model else {
            return false
        }
        send(.done)
        return true
    }
}

/// The stats store whose `bests(before:for:)` answers with `bests`, or throws, or waits at a gate first;
/// it counts the calls. Every other query is the in-memory store's (`base`).
actor BestsSession: StatsQueries {
    struct Unreadable: Error {}

    private let base: any StatsQueries
    private let answer: PersonalRecords.Bests?
    private let gate: Gate?
    /// The workouts `bests` was asked for, in call order.
    private(set) var askedFor: [WorkoutID] = []

    /// Answers `answer`, or throws `Unreadable` when it is nil; after `gate` opens, when there is one.
    init(base: any StatsQueries, answer: PersonalRecords.Bests?, gate: Gate? = nil) {
        self.base = base
        self.answer = answer
        self.gate = gate
    }

    func bests(before workout: WorkoutState, for _: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        askedFor.append(workout.id)
        await gate?.pass()
        guard let answer else {
            throw Unreadable()
        }
        return answer
    }

    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        try await base.lastPerformance(exerciseID: exerciseID)
    }

    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        try await base.bestSet(exerciseID: exerciseID)
    }

    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight? {
        try await base.bestE1RM(exerciseID: exerciseID)
    }

    func e1RMByWeek(
        exerciseID: ExerciseID,
        lastWeeks: Int,
        calendar: WeekCalendar
    ) async throws -> [WeekKey: Weight] {
        try await base.e1RMByWeek(exerciseID: exerciseID, lastWeeks: lastWeeks, calendar: calendar)
    }

    func weeklyVolume(in range: Range<Date>) async throws -> Volume {
        try await base.weeklyVolume(in: range)
    }

    func sessionsCompleted(in range: Range<Date>) async throws -> Int {
        try await base.sessionsCompleted(in: range)
    }

    func sessionCount(exerciseID: ExerciseID) async throws -> Int {
        try await base.sessionCount(exerciseID: exerciseID)
    }

    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord] {
        try await base.personalRecords(exerciseID: exerciseID)
    }

    func recentlyLogged(limit: Int) async throws -> [ExerciseID] {
        try await base.recentlyLogged(limit: limit)
    }
}
