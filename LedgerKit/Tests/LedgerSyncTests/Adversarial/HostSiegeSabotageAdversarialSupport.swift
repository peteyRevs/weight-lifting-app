import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization

/// A store that does not do what it says, to show that a siege notices (F10 S2 adversarial round 1). A host
/// over such a store cannot be right, so a siege that reports nothing about it would be judging nothing.
enum SiegeSabotage: String, Sendable, CaseIterable, CustomStringConvertible {
    /// Every fifth append answers as if it had stored its envelopes, and stores none.
    case forgetsAnAppend
    /// `materialize` returns and writes nothing.
    case neverSaves
    /// `compact` returns and drops nothing.
    case neverCompacts

    var description: String {
        rawValue
    }
}

struct SabotagedEventStore: WorkoutEventStore {
    let base: any WorkoutEventStore
    let sabotage: SiegeSabotage?
    private let appends = SeamCounter()

    func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        if sabotage == .forgetsAnAppend, appends.next().isMultiple(of: 5) {
            return envelopes
        }
        return try await base.append(envelopes)
    }

    func envelopes(for workout: WorkoutID) async throws -> [EventEnvelope] {
        try await base.envelopes(for: workout)
    }

    func unreadableCount(for workout: WorkoutID) async throws -> Int {
        try await base.unreadableCount(for: workout)
    }

    func highestSeq(for workout: WorkoutID, device: DeviceID) async throws -> UInt64? {
        try await base.highestSeq(for: workout, device: device)
    }

    func uncompactedWorkoutIDs() async throws -> [WorkoutID] {
        try await base.uncompactedWorkoutIDs()
    }

    func newestWallClock() async throws -> Date? {
        try await base.newestWallClock()
    }

    func compact(workout: WorkoutID) async throws {
        if sabotage != .neverCompacts {
            try await base.compact(workout: workout)
        }
    }
}

/// A history that takes every workout and keeps none.
struct SabotagedWorkoutRepository: WorkoutRepository {
    let base: any WorkoutRepository

    func materialize(_: WorkoutState, slotUpdates _: [Slot]) async throws {}

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
