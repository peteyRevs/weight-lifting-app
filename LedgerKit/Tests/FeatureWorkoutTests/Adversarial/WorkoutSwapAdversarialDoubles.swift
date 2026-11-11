import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

// G2, F10 S8b: the doubles and the bench of the swap's adversarial tests. Written by the tester from the
// S8 contract, before the implementer's tests and notes were read.

nonisolated struct SwapG2Refused: Error, Equatable {}

/// The exercises as the store reads them: the shipped catalog (or what the test gives), with every call
/// counted; a call can be made to throw, and the next `all()` can be made to wait until released.
actor SwapG2Exercises: ExerciseRepository {
    private var catalog: [Exercise]
    private(set) var allCalls = 0
    private(set) var exerciseCalls = 0
    private var failsAll = false
    private var failsExercise = false
    private var holdsNextAll = false
    private var throwsWhenReleased = false
    private var parked: CheckedContinuation<Void, Never>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []

    init(_ catalog: [Exercise]) {
        self.catalog = catalog
    }

    func set(catalog: [Exercise]) {
        self.catalog = catalog
    }

    func failAll(_ fails: Bool = true) {
        failsAll = fails
    }

    func failExercise(_ fails: Bool = true) {
        failsExercise = fails
    }

    /// The next `all()` waits until `release()`; with `throwing`, it then throws.
    func holdNextAll(throwing: Bool = false) {
        holdsNextAll = true
        throwsWhenReleased = throwing
    }

    func waitUntilHeld() async {
        guard parked == nil else {
            return
        }
        await withCheckedContinuation { arrivals.append($0) }
    }

    func release() {
        parked?.resume()
        parked = nil
    }

    func all() async throws -> [Exercise] {
        allCalls += 1
        if holdsNextAll {
            holdsNextAll = false
            let throwing = throwsWhenReleased
            await withCheckedContinuation { waiting in
                parked = waiting
                for arrival in arrivals {
                    arrival.resume()
                }
                arrivals = []
            }
            if throwing {
                throw SwapG2Refused()
            }
        }
        if failsAll {
            throw SwapG2Refused()
        }
        return ExerciseSearch.sorted(catalog)
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        exerciseCalls += 1
        if failsExercise {
            throw SwapG2Refused()
        }
        return catalog.first { $0.id == id }
    }

    func search(_: String, equipment _: Equipment?, muscle _: MuscleGroup?) async throws -> [Exercise] {
        throw SwapG2Refused()
    }

    func save(_: Exercise) async throws {
        throw SwapG2Refused()
    }

    func seedIfNeeded(_: [Exercise], version _: Int) async throws {}

    nonisolated func observeAll() -> AsyncStream<[Exercise]> {
        AsyncStream { $0.finish() }
    }
}

/// The stats as the swap reads them: a canned last session per exercise, and bests that are counted and can
/// fail. Everything else throws: the swap must not need it.
actor SwapG2Stats: StatsQueries {
    private var last: [ExerciseID: LastPerformance] = [:]
    private var failingLast: Set<ExerciseID> = []
    private(set) var lastCalls: [ExerciseID] = []
    private(set) var bestsCalls: [Set<ExerciseID>] = []
    private var failsBests = false
    private var canned = PersonalRecords.Bests()

    func set(last performance: LastPerformance?, for id: ExerciseID) {
        last[id] = performance
    }

    func failLast(for id: ExerciseID) {
        failingLast.insert(id)
    }

    func failBests(_ fails: Bool = true) {
        failsBests = fails
    }

    func set(bests: PersonalRecords.Bests) {
        canned = bests
    }

    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        lastCalls.append(exerciseID)
        if failingLast.contains(exerciseID) {
            throw SwapG2Refused()
        }
        return last[exerciseID]
    }

    func bests(before _: WorkoutState, for exerciseIDs: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        bestsCalls.append(exerciseIDs)
        if failsBests {
            throw SwapG2Refused()
        }
        var answer = PersonalRecords.Bests()
        for id in exerciseIDs {
            answer.e1RM[id] = canned.e1RM[id]
            answer.weightAtReps[id] = canned.weightAtReps[id]
        }
        return answer
    }

    func bestSet(exerciseID _: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        throw SwapG2Refused()
    }

    func bestSets() async throws -> [ExerciseID: BestSet] {
        throw SwapG2Refused()
    }

    func bestE1RM(exerciseID _: ExerciseID) async throws -> Weight? {
        throw SwapG2Refused()
    }

    func e1RMByWeek(
        exerciseID _: ExerciseID,
        lastWeeks _: Int,
        calendar _: WeekCalendar
    ) async throws -> [WeekKey: Weight] {
        throw SwapG2Refused()
    }

    func weeklyVolume(in _: Range<Date>) async throws -> Volume {
        throw SwapG2Refused()
    }

    func sessionsCompleted(in _: Range<Date>) async throws -> Int {
        throw SwapG2Refused()
    }

    func sessionCount(exerciseID _: ExerciseID) async throws -> Int {
        throw SwapG2Refused()
    }

    func personalRecords(exerciseID _: ExerciseID) async throws -> [PersonalRecord] {
        throw SwapG2Refused()
    }

    func recentlyLogged(limit _: Int) async throws -> [ExerciseID] {
        throw SwapG2Refused()
    }

    func exerciseSessions(exerciseID _: ExerciseID) async throws -> [ExerciseSession] {
        throw SwapG2Refused()
    }

    nonisolated func observeExerciseSessions(exerciseID _: ExerciseID) -> AsyncStream<[ExerciseSession]> {
        AsyncStream { $0.finish() }
    }

    nonisolated func observeLibraryStats(recentLimit _: Int) -> AsyncStream<LibraryStats> {
        AsyncStream { $0.finish() }
    }
}
