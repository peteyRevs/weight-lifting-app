import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F07 criterion 4: every repository contract the GRDB stores keep (`ExerciseRepositoryTests`,
/// `ProgramRepositoryTests`, `WorkoutRepositoryTests`, `StatsQueriesTests`, `WorkoutEventStoreTests`,
/// `SettingsRepositoryTests`) run against LedgerFakes' in-memory stores, each clause on a fresh store, so a fake
/// cannot drift from the real semantics (testing-strategy §2.2). The storage clauses (S1 fix round 1) hold the
/// fakes to the database's boundary too: exact weights, finite dates, encodings, and the slot's exercise.
@Suite("In-memory stores · the repository contracts", .tags(.persistence), .timeLimit(.minutes(1)))
struct InMemoryContractTests {
    /// Linked stores over one empty state holding `ProgramRepositoryContract.exercises`, as the GRDB suites'
    /// database does, the stats at `StatsQueriesContract.now`.
    static func stores() async throws -> InMemoryStores {
        let stores = InMemoryStores(now: { StatsQueriesContract.now })
        try await stores.exercises.seedIfNeeded(ProgramRepositoryContract.exercises, version: 1)
        return stores
    }

    static func history() async throws -> HistoryStores {
        let stores = try await stores()
        return HistoryStores(workouts: stores.workouts, stats: stores.stats, programs: stores.programs)
    }

    @Test("InMemoryExerciseRepository keeps the contract clause", arguments: ExerciseRepositoryContract.clauses)
    func exercises_keepTheContract(_ clause: ExerciseRepositoryContract.Clause) async throws {
        let issue = try await clause.check(InMemoryExerciseRepository())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemoryProgramRepository keeps the contract clause", arguments: ProgramRepositoryContract.clauses)
    func programs_keepTheContract(_ clause: ProgramRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Self.stores().programs)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemoryWorkoutRepository keeps the contract clause", arguments: WorkoutRepositoryContract.clauses)
    func workouts_keepTheContract(_ clause: WorkoutRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Self.history())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemoryStatsQueries keeps the contract clause", arguments: StatsQueriesContract.clauses)
    func stats_keepTheContract(_ clause: StatsQueriesContract.Clause) async throws {
        let issue = try await clause.check(Self.history())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemoryWorkoutEventStore keeps the contract clause", arguments: WorkoutEventStoreContract.clauses)
    func events_keepTheContract(_ clause: WorkoutEventStoreContract.Clause) async throws {
        let issue = try await clause.check(InMemoryWorkoutEventStore())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemorySettingsRepository keeps the contract clause", arguments: SettingsRepositoryContract.clauses)
    func settings_keepTheContract(_ clause: SettingsRepositoryContract.Clause) async throws {
        let issue = try await clause.check(InMemorySettingsRepository())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }
}

/// The storage clauses (S1 fix round 1: findings F7-1 to F7-4), on the same stores.
extension InMemoryContractTests {
    @Test("InMemoryExerciseRepository keeps the storage clause", arguments: ExerciseRepositoryContract.storageClauses)
    func exercises_keepTheStorageClauses(_ clause: ExerciseRepositoryContract.Clause) async throws {
        let issue = try await clause.check(InMemoryExerciseRepository())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test(
        "The linked InMemoryProgramRepository keeps the storage clause",
        arguments: ProgramRepositoryContract.storageClauses
    )
    func programs_keepTheStorageClauses(_ clause: ProgramRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Self.stores().programs)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemoryWorkoutRepository keeps the storage clause", arguments: WorkoutRepositoryContract.storageClauses)
    func workouts_keepTheStorageClauses(_ clause: WorkoutRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Self.history())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemoryWorkoutEventStore keeps the storage clause", arguments: WorkoutEventStoreContract.storageClauses)
    func events_keepTheStorageClauses(_ clause: WorkoutEventStoreContract.Clause) async throws {
        let issue = try await clause.check(InMemoryWorkoutEventStore())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemorySettingsRepository keeps the storage clause", arguments: SettingsRepositoryContract.storageClauses)
    func settings_keepTheStorageClauses(_ clause: SettingsRepositoryContract.Clause) async throws {
        let issue = try await clause.check(InMemorySettingsRepository())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("Without an exercise store, a program store checks no slot's exercise; seeded programs are never checked")
    func unlinkedPrograms_checkNoExercise() async throws {
        let program = try ProgramRepositoryContract.program()
        let unlinked = InMemoryProgramRepository()
        try await unlinked.save(program)
        let seeded = InMemoryStores(seed: InMemoryStores.Seed(programs: [program]))
        #expect(try await unlinked.active() == program)
        #expect(try await seeded.programs.active() == program)
        await #expect(throws: RepositoryError.unknownExercise(
            "exercise \(program.days[0].slots[0].exerciseID.rawValue.uuidString)"
        )) {
            try await seeded.programs.save(program)
        }
    }
}
