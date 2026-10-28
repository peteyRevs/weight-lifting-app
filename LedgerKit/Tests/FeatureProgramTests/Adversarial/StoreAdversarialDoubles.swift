import Foundation
import LedgerDomain
import Synchronization

// F11 S13 adversarial round 1: the program and workout stores the tester's store suites put between the store
// and the in-memory ones (`StoreAdversarialSupport.swift`).

/// A program store whose writes are written to `log`, in order, with the reads of the workouts.
nonisolated struct S13LoggedPrograms: ProgramRepository {
    let base: any ProgramRepository
    let log: S13Log

    func active() async throws -> Program? {
        try await base.active()
    }

    func save(_ program: Program) async throws {
        log.append("save")
        try await base.save(program)
    }

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        log.append("update")
        return try await base.update(id, change)
    }

    func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }

    func observeActive() -> AsyncStream<Program?> {
        base.observeActive()
    }
}

nonisolated struct S13LoggedWorkouts: WorkoutRepository {
    let base: any WorkoutRepository
    let log: S13Log

    func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
        log.append("workouts")
        return try await base.workouts(in: range)
    }

    func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog: Bool) async throws -> Bool {
        try await base.materialize(workout, slotUpdates: slotUpdates, droppingLog: droppingLog)
    }

    func workout(id: WorkoutID) async throws -> WorkoutState? {
        try await base.workout(id: id)
    }

    func recent(limit: Int) async throws -> [WorkoutState] {
        try await base.recent(limit: limit)
    }

    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
        try await base.updateSets(workoutExerciseID: workoutExerciseID, sets: sets)
    }

    func delete(id: WorkoutID) async throws {
        try await base.delete(id: id)
    }

    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        base.observeRecent(limit: limit)
    }

    func historyEntries() async throws -> [HistoryEntry] {
        try await base.historyEntries()
    }

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        base.observeHistoryEntries()
    }
}

/// A program store that throws `error` from the next `times` updates, before anything is stored, while its task
/// is not cancelled; then passes every call on.
final nonisolated class S13ThrowingPrograms: ProgramRepository, Sendable {
    let base: any ProgramRepository
    private let remaining: Mutex<Int>
    private let error: @Sendable () -> any Error

    init(base: any ProgramRepository, times: Int, error: @escaping @Sendable () -> any Error) {
        self.base = base
        remaining = Mutex(times)
        self.error = error
    }

    var calls: Int {
        callCount.withLock { $0 }
    }

    private let callCount = Mutex(0)

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        callCount.withLock { $0 += 1 }
        let throwsNow = remaining.withLock { left in
            guard left > 0 else {
                return false
            }
            left -= 1
            return true
        }
        if throwsNow {
            throw error()
        }
        return try await base.update(id, change)
    }

    func active() async throws -> Program? {
        try await base.active()
    }

    func save(_ program: Program) async throws {
        try await base.save(program)
    }

    func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }

    func observeActive() -> AsyncStream<Program?> {
        base.observeActive()
    }
}

/// A program store whose first `endings` observations end at once (a database observation whose read failed),
/// and whose later ones are the base's.
final nonisolated class S13EndingPrograms: ProgramRepository, Sendable {
    let base: any ProgramRepository
    private let endings: Mutex<Int>

    init(base: any ProgramRepository, endings: Int) {
        self.base = base
        self.endings = Mutex(endings)
    }

    func observeActive() -> AsyncStream<Program?> {
        let ends = endings.withLock { left in
            guard left > 0 else {
                return false
            }
            left -= 1
            return true
        }
        return ends ? AsyncStream { $0.finish() } : base.observeActive()
    }

    func active() async throws -> Program? {
        try await base.active()
    }

    func save(_ program: Program) async throws {
        try await base.save(program)
    }

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        try await base.update(id, change)
    }

    func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }
}
