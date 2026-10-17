import Foundation
import LedgerDomain

// The stores' live values until the composition root binds the GRDB ones (F07 S2). Each method logs at fault
// level and throws `LedgerDependencyError.unimplemented(key:)`; each `observe…()` logs and ends at once.

struct UnimplementedExerciseRepository: ExerciseRepository {
    let stub = Unimplemented(key: "exerciseRepository")

    func all() async throws -> [Exercise] {
        throw stub.failure()
    }

    func exercise(id _: ExerciseID) async throws -> Exercise? {
        throw stub.failure()
    }

    func search(_: String, equipment _: Equipment?, muscle _: MuscleGroup?) async throws -> [Exercise] {
        throw stub.failure()
    }

    func save(_: Exercise) async throws {
        throw stub.failure()
    }

    func seedIfNeeded(_: [Exercise], version _: Int) async throws {
        throw stub.failure()
    }

    func observeAll() -> AsyncStream<[Exercise]> {
        stub.emptyStream()
    }
}

struct UnimplementedProgramRepository: ProgramRepository {
    let stub = Unimplemented(key: "programRepository")

    func active() async throws -> Program? {
        throw stub.failure()
    }

    func save(_: Program) async throws {
        throw stub.failure()
    }

    func update(_: ProgramID, _: @Sendable (Program) throws -> Program) async throws -> Program {
        throw stub.failure()
    }

    func setActive(_: ProgramID) async throws {
        throw stub.failure()
    }

    func delete(_: ProgramID) async throws {
        throw stub.failure()
    }

    func observeActive() -> AsyncStream<Program?> {
        stub.emptyStream()
    }
}

struct UnimplementedWorkoutRepository: WorkoutRepository {
    let stub = Unimplemented(key: "workoutRepository")

    func materialize(_: WorkoutState, slotUpdates _: [Slot], droppingLog _: Bool) async throws -> Bool {
        throw stub.failure()
    }

    func workout(id _: WorkoutID) async throws -> WorkoutState? {
        throw stub.failure()
    }

    func recent(limit _: Int) async throws -> [WorkoutState] {
        throw stub.failure()
    }

    func workouts(in _: Range<Date>) async throws -> [WorkoutState] {
        throw stub.failure()
    }

    func updateSets(workoutExerciseID _: WorkoutExerciseID, sets _: [LoggedSet]) async throws {
        throw stub.failure()
    }

    func delete(id _: WorkoutID) async throws {
        throw stub.failure()
    }

    func observeRecent(limit _: Int) -> AsyncStream<[WorkoutState]> {
        stub.emptyStream()
    }
}

struct UnimplementedSettingsRepository: SettingsRepository {
    let stub = Unimplemented(key: "settingsRepository")

    func load() async throws -> Settings {
        throw stub.failure()
    }

    func save(_: Settings) async throws {
        throw stub.failure()
    }

    func observe() -> AsyncStream<Settings> {
        stub.emptyStream()
    }
}

struct UnimplementedWorkoutEventStore: WorkoutEventStore {
    let stub = Unimplemented(key: "workoutEventStore")

    func append(_: [EventEnvelope]) async throws -> [EventEnvelope] {
        throw stub.failure()
    }

    func envelopes(for _: WorkoutID) async throws -> [EventEnvelope] {
        throw stub.failure()
    }

    func unreadableCount(for _: WorkoutID) async throws -> Int {
        throw stub.failure()
    }

    func highestSeq(for _: WorkoutID, device _: DeviceID) async throws -> UInt64? {
        throw stub.failure()
    }

    func uncompactedWorkoutIDs() async throws -> [WorkoutID] {
        throw stub.failure()
    }

    func newestWallClock() async throws -> Date? {
        throw stub.failure()
    }

    func compact(workout _: WorkoutID) async throws {
        throw stub.failure()
    }
}
