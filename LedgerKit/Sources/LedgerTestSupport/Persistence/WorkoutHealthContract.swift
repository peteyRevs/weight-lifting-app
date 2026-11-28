import Foundation
import LedgerDomain

/// The stores a `WorkoutHealthContract` clause runs against, over one fresh store holding
/// `ProgramRepositoryContract.exercises`: `health` is the same repository as `history.workouts`, and `companion`'s
/// finished logs are the ones `pendingHealth()` reads.
public struct WorkoutHealthStores: Sendable {
    public let health: any WorkoutHealthRepository
    public let history: HistoryStores
    public let companion: any CompanionStore

    public init(health: any WorkoutHealthRepository, history: HistoryStores, companion: any CompanionStore) {
        self.health = health
        self.history = history
        self.companion = companion
    }
}

/// `WorkoutHealthRepository`'s contract as named clauses (F19 S3b, criterion 9). `GRDBWorkoutRepository` and
/// `InMemoryWorkoutRepository` each run every clause in `LedgerPersistenceTests`.
public enum WorkoutHealthContract {
    public typealias Clause = ContractClause<WorkoutHealthStores>

    public static let clauses: [Clause] = [
        Clause("saved statistics read back exactly; saving again replaces every field, a nil included", upserts),
        Clause("a workout not stored, or deleted, throws missingRow; a deleted workout keeps its statistics", refuses),
        Clause(
            "pending: live workouts whose log names a HealthKit UUID and that have no statistics, oldest log first",
            listsPending
        )
    ]

    /// Statistics as the watch's HealthKit workout `number` has them.
    public static func health(_ number: Int) -> WorkoutHealth {
        WorkoutHealth(
            healthKitUUID: EventBuilders.uuid(0xAB00 + number),
            avgHeartRate: 120 + number,
            maxHeartRate: 170 + number,
            activeEnergyKcal: 400 + number
        )
    }

    /// The watch's record of `workout`, naming `health(number)`'s HealthKit workout, or none.
    public static func record(of workout: WorkoutID, health number: Int?) -> FinishedWorkoutRecord {
        FinishedWorkoutRecord(
            workoutID: workout,
            log: [],
            healthKitUUID: number.map { health($0).healthKitUUID },
            finishedAt: EventBuilders.start,
            device: EventBuilders.watch
        )
    }

    static func upserts(_ stores: WorkoutHealthStores) async throws -> String? {
        let workout = WorkoutRepositoryContract.workout(number: 1)
        let other = WorkoutRepositoryContract.workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(3600))
        try await stores.history.materialize(workout)
        try await stores.history.materialize(other)
        let before = try await stores.health.health(of: workout.id)
        try await stores.health.saveHealth(health(1), of: workout.id)
        let saved = try await stores.health.health(of: workout.id)
        let replacement = WorkoutHealth(
            healthKitUUID: health(2).healthKitUUID,
            avgHeartRate: nil,
            maxHeartRate: 181,
            activeEnergyKcal: nil
        )
        try await stores.health.saveHealth(replacement, of: workout.id)
        return try await ContractCheck.first(
            ContractCheck.expect(before, nil, "before a save"),
            ContractCheck.expect(saved, health(1), "after a save"),
            ContractCheck.expect(stores.health.health(of: workout.id), replacement, "saved again"),
            ContractCheck.expect(stores.health.health(of: other.id), nil, "another workout")
        )
    }

    static func refuses(_ stores: WorkoutHealthStores) async throws -> String? {
        let unknown = WorkoutRepositoryContract.workout(number: 1).id
        let deleted = WorkoutRepositoryContract.workout(number: 2)
        let kept = WorkoutRepositoryContract.workout(number: 3, endedAt: EventBuilders.start.addingTimeInterval(3600))
        for workout in [deleted, kept] {
            try await stores.history.materialize(workout)
        }
        try await stores.health.saveHealth(health(3), of: kept.id)
        try await stores.history.workouts.delete(id: kept.id)
        try await stores.history.workouts.delete(id: deleted.id)
        let refusals = await ContractCheck.first(
            ContractCheck.expectError(RepositoryError.missingRow("workout \(unknown.rawValue.uuidString)")) {
                try await stores.health.saveHealth(health(1), of: unknown)
            },
            ContractCheck.expectError(RepositoryError.missingRow("workout \(deleted.id.rawValue.uuidString)")) {
                try await stores.health.saveHealth(health(2), of: deleted.id)
            },
            ContractCheck.expectError(RepositoryError.missingRow("workout \(kept.id.rawValue.uuidString)")) {
                try await stores.health.saveHealth(health(4), of: kept.id)
            }
        )
        try await stores.history.materialize(deleted)
        return try await ContractCheck.first(
            refusals,
            ContractCheck.expect(stores.health.health(of: deleted.id), nil, "the deleted workout, brought back"),
            ContractCheck.expect(stores.health.health(of: kept.id), health(3), "the workout deleted after its save")
        )
    }

    static func listsPending(_ stores: WorkoutHealthStores) async throws -> String? {
        let start = EventBuilders.start
        let workouts = (1 ... 7).map { number in
            WorkoutRepositoryContract.workout(number: number, endedAt: start.addingTimeInterval(Double(number) * 3600))
        }
        for workout in workouts.dropLast() {
            try await stores.history.materialize(workout)
        }
        // 1 and 2 share a created-at, so the workout id orders them; 3 has no HealthKit workout; 4 has its statistics;
        // 5 is deleted; 6 is acknowledged; 7 is not stored.
        let offsets: [TimeInterval] = [0, 0, -600, -600, -600, -60, -600]
        for (index, workout) in workouts.enumerated() {
            try await stores.companion.saveFinishedLog(
                record(of: workout.id, health: index == 2 ? nil : index + 1),
                createdAt: start.addingTimeInterval(offsets[index])
            )
        }
        try await stores.health.saveHealth(health(4), of: workouts[3].id)
        try await stores.history.workouts.delete(id: workouts[4].id)
        try await stores.companion.acknowledge([workouts[5].id], at: start)
        let byID = [0, 1].sorted { workouts[$0].id.rawValue.uuidString < workouts[$1].id.rawValue.uuidString }
        let expected = ([5] + byID).map { index in
            PendingHealth(
                workoutID: workouts[index].id,
                healthKitUUID: health(index + 1).healthKitUUID,
                createdAt: start.addingTimeInterval(offsets[index])
            )
        }
        let pending = try await stores.health.pendingHealth()
        try await stores.health.saveHealth(health(6), of: workouts[5].id)
        return try await ContractCheck.first(
            ContractCheck.expect(pending, expected, "the pending list"),
            ContractCheck.expect(
                stores.health.pendingHealth(),
                Array(expected.dropFirst()),
                "after a save, the pending list"
            )
        )
    }
}
