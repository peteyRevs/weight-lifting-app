import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBWorkoutRepository` as `WorkoutHealthRepository` (F19 S3b, criterion 9): the contract, then what only the
/// database can do: the row's columns and stamps, v001's row, and a pending log it cannot read.
@Suite("GRDBWorkoutRepository · health", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutHealthTests {
    static func stores() async throws -> (WorkoutHealthStores, Repositories) {
        let repositories = try await Repositories.withProgramExercises()
        let stores = WorkoutHealthStores(
            health: repositories.workouts,
            history: repositories.history,
            companion: GRDBCompanionStore(repositories.queue, now: repositories.clock.now)
        )
        return (stores, repositories)
    }

    @Test("The GRDB repository keeps the contract clause", arguments: WorkoutHealthContract.clauses)
    func contract_clauseHolds(_ clause: WorkoutHealthContract.Clause) async throws {
        let issue = try await clause.check(Self.stores().0)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("A save is one row: the UUID as text, energy as REAL; saved again, created_at stays and updated_at moves")
    func saveHealth_columns() async throws {
        let (stores, repositories) = try await Self.stores()
        let workout = WorkoutRepositoryContract.workout()
        try await stores.history.materialize(workout)
        let created = repositories.clock.timestamp
        try await stores.health.saveHealth(WorkoutHealthContract.health(1), of: workout.id)
        repositories.clock.advance()
        try await stores.health.saveHealth(WorkoutHealthContract.health(2), of: workout.id)
        let row = try await repositories.texts("""
        SELECT workout_id || ' ' || avg_heart_rate || ' ' || max_heart_rate || ' ' || quote(active_energy_kcal) || ' '
            || hk_workout_uuid || ' ' || created_at || ' ' || updated_at FROM workout_health
        """)
        let uuid = WorkoutHealthContract.health(2).healthKitUUID.uuidString
        let updated = repositories.clock.timestamp
        #expect(row == ["\(workout.id.rawValue.uuidString) 122 172 402.0 \(uuid) \(created) \(updated)"])
    }

    @Test("What HealthKit read saves as its statistics, without the dates")
    func saveHealth_ofARecord() async throws {
        let (stores, _) = try await Self.stores()
        let workout = WorkoutRepositoryContract.workout()
        try await stores.history.materialize(workout)
        let uuid = EventBuilders.uuid(0xAB07)
        let record = HealthWorkoutRecord(
            healthKitUUID: uuid, start: EventBuilders.start, end: EventBuilders.start.addingTimeInterval(3600),
            avgHeartRate: 131, maxHeartRate: nil, activeEnergyKcal: 388
        )
        try await stores.health.saveHealth(WorkoutHealth(record), of: workout.id)
        let expected = WorkoutHealth(healthKitUUID: uuid, avgHeartRate: 131, maxHeartRate: nil, activeEnergyKcal: 388)
        #expect(try await stores.health.health(of: workout.id) == expected)
    }

    @Test("v001's row reads back, its fractional energy rounded; a NULL UUID or text energy throws malformedColumn")
    func v001Row_reads() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try LedgerDatabase.open(at: MigrationCompatibilityTests.fixtureCopy(in: directory))
        let workouts = GRDBWorkoutRepository(queue)
        let edited = MigrationCompatibilityTests.edited
        #expect(try await workouts.health(of: edited) == WorkoutHealth(
            healthKitUUID: EventBuilders.uuid(0xAB1E),
            avgHeartRate: 128,
            maxHeartRate: 171,
            activeEnergyKcal: 413
        ))
        try await queue.write { try $0.execute(sql: "UPDATE workout_health SET hk_workout_uuid = NULL") }
        await #expect(throws: LedgerPersistenceError.malformedColumn("workout_health.hk_workout_uuid")) {
            try await workouts.health(of: edited)
        }
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE workout_health SET hk_workout_uuid = ?, active_energy_kcal = 'x'",
                arguments: [EventBuilders.uuid(0xAB1E).uuidString]
            )
        }
        await #expect(throws: LedgerPersistenceError.malformedColumn("workout_health.active_energy_kcal")) {
            try await workouts.health(of: edited)
        }
    }

    @Test("A pending log whose UUID it cannot read is left out and stays stored; the rest are listed")
    func unreadablePendingLog_isLeftOut() async throws {
        let (stores, repositories) = try await Self.stores()
        let workouts = (1 ... 2).map { number in
            WorkoutRepositoryContract.workout(number: number, endedAt: EventBuilders.start.addingTimeInterval(
                Double(number) * 3600
            ))
        }
        for workout in workouts {
            try await stores.history.materialize(workout)
            try await stores.companion.saveFinishedLog(
                WorkoutHealthContract.record(of: workout.id, health: 1),
                createdAt: EventBuilders.start
            )
        }
        try await repositories.execute(
            "UPDATE finished_log SET health_uuid = 'not a uuid' WHERE workout_id = ?",
            [workouts[0].id.rawValue.uuidString]
        )
        #expect(try await stores.health.pendingHealth().map(\.workoutID) == [workouts[1].id])
        #expect(try await repositories.count("SELECT COUNT(*) FROM finished_log") == 2)
    }
}
