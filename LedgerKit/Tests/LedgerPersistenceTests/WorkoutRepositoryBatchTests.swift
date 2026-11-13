import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBWorkoutRepository.materialize(_:)` of several workouts (F15 S1, G2-1): one write transaction, which stores
/// each workout as a save of it alone would, or none of them.
@Suite("GRDBWorkoutRepository · several workouts in one write", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutRepositoryBatchTests {
    typealias Contract = WorkoutRepositoryContract

    /// A database with the contract program, the contract workout, and the one of two days before it.
    private static func arranged() async throws -> (Repositories, [WorkoutState]) {
        let repositories = try await Repositories.withProgramExercises()
        try await repositories.programs.save(ProgramRepositoryContract.program())
        let workout = Contract.workout()
        return (repositories, [WorkoutRepositoryTests.earlier(than: workout), workout])
    }

    @Test("Two workouts are stored in one transaction, with the records a save of each would derive")
    func severalWorkouts_storedInOneTransaction() async throws {
        let (repositories, workouts) = try await Self.arranged()
        let transactions = try await repositories.statements(startingWith: "") {
            try await repositories.workouts.materialize(workouts)
        }.filter { $0.hasPrefix("BEGIN") || $0.hasPrefix("COMMIT") }
        #expect(transactions == ["BEGIN IMMEDIATE TRANSACTION", "COMMIT TRANSACTION"])
        #expect(try await repositories.workouts.recent(limit: 5) == workouts.reversed())
        let bench = workouts[1].exercises[0].exerciseID
        let records = WorkoutRepositoryTests.records(of: workouts[1])
        #expect(try await repositories.stats.personalRecords(exerciseID: bench) == records)
    }

    @Test("A failure at the second workout leaves no row of the first")
    func failureAtTheSecond_leavesNone() async throws {
        let (repositories, workouts) = try await Self.arranged()
        let before = try await repositories.texts(WorkoutRepositoryTests.everyRow)
        try await repositories.execute("""
        CREATE TRIGGER injected BEFORE INSERT ON workout WHEN (SELECT COUNT(*) FROM workout) >= 1
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END
        """)
        await #expect(throws: DatabaseError.self) {
            try await repositories.workouts.materialize(workouts)
        }
        #expect(try await repositories.texts(WorkoutRepositoryTests.everyRow) == before)
    }
}
