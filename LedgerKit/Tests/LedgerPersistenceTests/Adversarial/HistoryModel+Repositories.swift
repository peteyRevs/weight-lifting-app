import Foundation
import LedgerDomain
import LedgerPersistence

/// `HistoryModel` as the workout repository, and as the small program repository the misses need.
extension HistoryModel: WorkoutRepository {
    func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog _: Bool) async throws -> Bool {
        guard workout.phase == .finished, workout.endedAt != nil else {
            throw LedgerPersistenceError.notFinished("workout \(workout.id.rawValue.uuidString)")
        }
        try write { state in
            try store(workout, in: &state)
            redetect(after: workout.id, in: &state)
            writeMisses(of: slotUpdates, in: &state)
        }
        return false
    }

    func workout(id: WorkoutID) async throws -> WorkoutState? {
        state.withLock { state in state.entries[id].flatMap { $0.isDeleted ? nil : $0.state } }
    }

    func recent(limit: Int) async throws -> [WorkoutState] {
        state.withLock { recent(limit, in: $0) }
    }

    func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
        state.withLock { state in live(state).filter { contains(range, date($0)) } }
    }

    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
        try write { state in
            let owner = state.entries.values.first { entry in
                !entry.isDeleted && entry.state.exercises.contains { $0.id == workoutExerciseID }
            }
            guard var workout = owner?.state,
                  let index = workout.exercises.firstIndex(where: { $0.id == workoutExerciseID })
            else {
                throw LedgerPersistenceError.missingRow("workout_exercise \(workoutExerciseID.rawValue.uuidString)")
            }
            workout.exercises[index].sets = sets
            try store(workout, in: &state)
            if has(.editDropsRecords) {
                state.entries[workout.id]?.records = []
            } else {
                redetect(after: workout.id, in: &state)
            }
        }
    }

    func delete(id: WorkoutID) async throws {
        try write { state in
            guard has(.hardDelete) else {
                state.entries[id]?.isDeleted = true
                redetect(after: id, in: &state)
                return
            }
            state.entries[id] = nil
            state.exerciseOwners = state.exerciseOwners.filter { $0.value != id }
            state.setOwners = state.setOwners.filter { $0.value != id }
            redetect(after: id, in: &state)
        }
    }

    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        let (stream, continuation) = AsyncStream<[WorkoutState]>.makeStream()
        state.withLock { state in
            let first = recent(limit, in: state)
            continuation.yield(first)
            state.observers.append(Observer(limit: limit, continuation: continuation, last: first))
        }
        return stream
    }

    /// The live workouts' entries with the records each holds (F13 S1). The History list's clauses run on the
    /// stores, not on this model.
    func historyEntries() async throws -> [HistoryEntry] {
        state.withLock { state in
            live(state).map { HistoryEntry($0, prCount: state.entries[$0.id]?.records.count ?? 0) }
        }
    }

    /// Not modelled: a stream that ends at once, as a failed observation's does.
    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        AsyncStream { $0.finish() }
    }

    func observeWorkout(id _: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        AsyncStream { $0.finish() }
    }
}

extension HistoryModel: ProgramRepository {
    func active() async throws -> Program? {
        state.withLock { state in state.programs.values.first(where: \.isActive) }
    }

    func save(_ program: Program) async throws {
        state.withLock { state in
            if program.isActive {
                for id in state.programs.keys {
                    state.programs[id]?.isActive = false
                }
            }
            state.programs[program.id] = program
        }
    }

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        try state.withLock { state in
            guard let stored = state.programs[id] else {
                throw LedgerPersistenceError.missingRow("program \(id.rawValue.uuidString)")
            }
            let changed = try change(stored)
            state.programs[id] = changed
            return changed
        }
    }

    func setActive(_ id: ProgramID) async throws {
        try state.withLock { state in
            guard state.programs[id] != nil else {
                throw LedgerPersistenceError.missingRow("program \(id.rawValue.uuidString)")
            }
            for key in state.programs.keys {
                state.programs[key]?.isActive = key == id
            }
        }
    }

    func delete(_ id: ProgramID) async throws {
        state.withLock { state in state.programs[id] = nil }
    }

    func observeActive() -> AsyncStream<Program?> {
        let current = state.withLock { state in state.programs.values.first(where: \.isActive) }
        return AsyncStream { continuation in
            continuation.yield(current)
            continuation.finish()
        }
    }
}
