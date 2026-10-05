import Foundation
import LedgerDomain

/// The three stores a session host is built over, each behind one `StoreProbe`.
public struct ProbedStores: Sendable {
    public let probe: StoreProbe
    public let events: ProbedEventStore
    public let workouts: ProbedWorkoutRepository
    public let programs: ProbedProgramRepository

    /// - Parameter yields: how often each call gives way (`Task.yield()`) before it reaches its store.
    public init(
        events: any WorkoutEventStore,
        workouts: any WorkoutRepository,
        programs: any ProgramRepository,
        yields: Int = 0
    ) {
        let shared = StoreProbe()
        probe = shared
        self.events = ProbedEventStore(base: events, probe: shared, yields: yields)
        self.workouts = ProbedWorkoutRepository(base: workouts, probe: shared, yields: yields)
        self.programs = ProbedProgramRepository(base: programs, probe: shared, yields: yields)
    }
}

/// Runs `body`, a store's call, between the probe's two halves, after giving way `yields` times.
private func probed<Value: Sendable>(
    _ call: StoreProbe.Call,
    _ probe: StoreProbe,
    _ yields: Int,
    _ body: () async throws -> Value
) async throws -> Value {
    for _ in 0 ..< yields {
        await Task.yield()
    }
    try await probe.enter(call)
    let value = try await body()
    try await probe.leave(call)
    return value
}

public struct ProbedEventStore: WorkoutEventStore {
    let base: any WorkoutEventStore
    let probe: StoreProbe
    let yields: Int

    public func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        try await probed(.append, probe, yields) { try await base.append(envelopes) }
    }

    public func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope] {
        try await probed(.envelopes, probe, yields) { try await base.envelopes(for: workout) }
    }

    public func unreadableCount(for workout: WorkoutID) async throws -> Int {
        try await probed(.unreadableCount, probe, yields) {
            if let pretended = await probe.unreadableOverride() {
                return pretended
            }
            return try await base.unreadableCount(for: workout)
        }
    }

    public func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64? {
        try await probed(.highestSeq, probe, yields) { try await base.highestSeq(for: workout, device: device) }
    }

    public func uncompactedWorkoutIDs() async throws -> [WorkoutID] {
        try await probed(.uncompactedWorkoutIDs, probe, yields) { try await base.uncompactedWorkoutIDs() }
    }

    public func newestWallClock() async throws -> Date? {
        try await probed(.newestWallClock, probe, yields) { try await base.newestWallClock() }
    }

    public func compact(workout: WorkoutID) async throws {
        try await probed(.compact, probe, yields) { try await base.compact(workout: workout) }
    }
}

/// Only `materialize`, the one call a session host makes, goes through the probe. It is passed on as it
/// came, so a host over probed stores of one database still saves a workout and drops its log in one
/// transaction, a fault on `.materialize` fails both, and the answer is the wrapped repository's.
public struct ProbedWorkoutRepository: WorkoutRepository {
    let base: any WorkoutRepository
    let probe: StoreProbe
    let yields: Int

    public func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog: Bool) async throws -> Bool {
        try await probed(.materialize, probe, yields) {
            try await base.materialize(workout, slotUpdates: slotUpdates, droppingLog: droppingLog)
        }
    }

    public func workout(id: WorkoutID) async throws -> WorkoutState? {
        try await base.workout(id: id)
    }

    public func recent(limit: Int) async throws -> [WorkoutState] {
        try await base.recent(limit: limit)
    }

    public func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
        try await base.workouts(in: range)
    }

    public func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
        try await base.updateSets(workoutExerciseID: workoutExerciseID, sets: sets)
    }

    public func delete(id: WorkoutID) async throws {
        try await base.delete(id: id)
    }

    public func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        base.observeRecent(limit: limit)
    }
}

/// Only `active()`, the one call a session host makes, goes through the probe.
public struct ProbedProgramRepository: ProgramRepository {
    let base: any ProgramRepository
    let probe: StoreProbe
    let yields: Int

    public func active() async throws -> Program? {
        try await probed(.activeProgram, probe, yields) { try await base.active() }
    }

    public func save(_ program: Program) async throws {
        try await base.save(program)
    }

    public func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    public func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }

    public func observeActive() -> AsyncStream<Program?> {
        base.observeActive()
    }
}
