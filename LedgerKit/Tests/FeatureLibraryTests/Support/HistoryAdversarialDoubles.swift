import Foundation
import LedgerDomain

// The doubles of `ExerciseHistoryAdversarialTests` (F12 S2, G2): a gate on the records read, and an exercise
// repository whose live list the test sends.

/// Holds the first records read until released, or fails the first `failures` of them. Since F12-S2-R1-3 the store
/// reads only the records; the sessions are the observation's.
final nonisolated class RecordsGate: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: Int
    private var holdsFirst: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private var released = false

    init(failures: Int = 0, holdsFirst: Bool = false) {
        self.failures = failures
        self.holdsFirst = holdsFirst
    }

    var isHolding: Bool {
        lock.withLock { waiter != nil }
    }

    /// Whether this read fails; a held read returns once released.
    func pass() async -> Bool {
        let fails = lock.withLock {
            defer { failures -= 1 }
            return failures > 0
        }
        let holds = lock.withLock {
            defer { holdsFirst = false }
            return holdsFirst && !released
        }
        if holds {
            await withCheckedContinuation { continuation in
                let resume = lock.withLock {
                    if released {
                        return true
                    }
                    waiter = continuation
                    return false
                }
                if resume {
                    continuation.resume()
                }
            }
        }
        return !fails
    }

    func release() {
        let waiting = lock.withLock {
            released = true
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume()
    }
}

/// The stats of `base`, with its records read through `gate`.
nonisolated struct GatedRecords: StatsQueries {
    let base: any StatsQueries
    let gate: RecordsGate

    func exerciseSessions(exerciseID: ExerciseID) async throws -> [ExerciseSession] {
        try await base.exerciseSessions(exerciseID: exerciseID)
    }

    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        try await base.lastPerformance(exerciseID: exerciseID)
    }

    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        try await base.bestSet(exerciseID: exerciseID)
    }

    func bestSets() async throws -> [ExerciseID: BestSet] {
        try await base.bestSets()
    }

    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight? {
        try await base.bestE1RM(exerciseID: exerciseID)
    }

    func e1RMByWeek(exerciseID: ExerciseID, lastWeeks: Int, calendar: WeekCalendar) async throws -> [WeekKey: Weight] {
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

    /// Read first, then held: a held read returns what was stored before the hold, as a slow database read would.
    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord] {
        let records = try await base.personalRecords(exerciseID: exerciseID)
        guard await gate.pass() else {
            throw UnreadableRecords.Unreadable()
        }
        return records
    }

    func bests(before workout: WorkoutState, for exerciseIDs: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        try await base.bests(before: workout, for: exerciseIDs)
    }

    func recentlyLogged(limit: Int) async throws -> [ExerciseID] {
        try await base.recentlyLogged(limit: limit)
    }

    func observeExerciseSessions(exerciseID: ExerciseID) -> AsyncStream<[ExerciseSession]> {
        base.observeExerciseSessions(exerciseID: exerciseID)
    }

    func observeLibraryStats(recentLimit: Int) -> AsyncStream<LibraryStats> {
        base.observeLibraryStats(recentLimit: recentLimit)
    }
}

/// Exercises whose live list the test sends: the repository has no delete (F29), so this is how one is taken away
/// while a history is up. Only `observeAll` is read by the history's store.
final nonisolated class ScriptedExercises: ExerciseRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: [Exercise] = []
    private var continuations: [AsyncStream<[Exercise]>.Continuation] = []

    func send(_ exercises: [Exercise]) {
        let targets = lock.withLock {
            latest = exercises
            return continuations
        }
        for continuation in targets {
            continuation.yield(exercises)
        }
    }

    func all() async throws -> [Exercise] {
        lock.withLock { latest }
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        lock.withLock { latest.first { $0.id == id } }
    }

    func search(_: String, equipment _: Equipment?, muscle _: MuscleGroup?) async throws -> [Exercise] {
        lock.withLock { latest }
    }

    func save(_: Exercise) async throws {}

    func seedIfNeeded(_: [Exercise], version _: Int) async throws {}

    func observeAll() -> AsyncStream<[Exercise]> {
        let (stream, continuation) = AsyncStream<[Exercise]>.makeStream()
        let now = lock.withLock {
            continuations.append(continuation)
            return latest
        }
        continuation.yield(now)
        return stream
    }
}

/// `eventually`, bounded: whether `condition` came to hold within `seconds`, polled every 10 ms. A test that
/// expects a change the store may never make fails in seconds, not at the suite's time limit.
@MainActor
func eventually(within seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< Int(seconds * 100) {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
