import Foundation
import LedgerDomain
import LedgerTestSupport

/// One host's way to its stores: the siege, the host's generation, and how often each call gives way first.
struct SiegeGate: Sendable {
    let siege: Siege
    let generation: Int
    let yields: Int

    func pass<Value: Sendable>(
        _ call: SiegeCall,
        _ body: @Sendable () async throws -> Value
    ) async throws -> Value {
        let fault = try await siege.enter(call, generation)
        for _ in 0 ..< yields {
            await Task.yield()
        }
        let value = try await body()
        try await siege.leave(call, fault)
        return value
    }
}

struct SiegeEventStore: WorkoutEventStore {
    let base: any WorkoutEventStore
    let gate: SiegeGate

    func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        try await gate.pass(.append) {
            let fresh = try await base.append(envelopes)
            await gate.siege.took(fresh)
            return fresh
        }
    }

    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope] {
        try await gate.pass(.envelopes) { try await base.envelopes(for: workout) }
    }

    func unreadableCount(for workout: WorkoutID) async throws -> Int {
        try await gate.pass(.unreadableCount) { try await base.unreadableCount(for: workout) }
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64? {
        try await gate.pass(.highestSeq) { try await base.highestSeq(for: workout, device: device) }
    }

    func uncompactedWorkoutIDs() async throws -> [WorkoutID] {
        try await gate.pass(.uncompactedWorkoutIDs) { try await base.uncompactedWorkoutIDs() }
    }

    func newestWallClock() async throws -> Date? {
        try await gate.pass(.newestWallClock) { try await base.newestWallClock() }
    }

    func compact(workout: WorkoutID) async throws {
        try await gate.pass(.compact) {
            try await base.compact(workout: workout)
            await gate.siege.compacted(workout)
        }
    }
}

/// Only `materialize`, the one call a host may make, goes through the gate.
struct SiegeWorkoutRepository: WorkoutRepository {
    let base: any WorkoutRepository
    let gate: SiegeGate
    /// Whether the save that drops the log is passed on to the store as one call (F10 S3): the stores are
    /// then one database to the host, as the app's are. Otherwise this is a wrapper of before S3, the host
    /// is told the log is still there, and it compacts it in a second call, which can fail by itself.
    var isLinked = false

    func materialize(_ workout: WorkoutState, slotUpdates: [Slot]) async throws {
        try await gate.pass(.materialize) {
            try await base.materialize(workout, slotUpdates: slotUpdates)
            await gate.siege.wrote(workout, slotUpdates)
        }
    }

    func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog: Bool) async throws -> Bool {
        guard isLinked else {
            try await materialize(workout, slotUpdates: slotUpdates)
            return false
        }
        return try await gate.pass(.materialize) {
            let dropped = try await base.materialize(workout, slotUpdates: slotUpdates, droppingLog: droppingLog)
            await gate.siege.wrote(workout, slotUpdates)
            if dropped {
                await gate.siege.compacted(workout.id)
            }
            return dropped
        }
    }

    func workout(id: WorkoutID) async throws -> WorkoutState? {
        try await base.workout(id: id)
    }

    func recent(limit: Int) async throws -> [WorkoutState] {
        try await base.recent(limit: limit)
    }

    func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
        try await base.workouts(in: range)
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
}

/// Only `active()` goes through the gate.
struct SiegeProgramRepository: ProgramRepository {
    let base: any ProgramRepository
    let gate: SiegeGate

    func active() async throws -> Program? {
        try await gate.pass(.activeProgram) { try await base.active() }
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
