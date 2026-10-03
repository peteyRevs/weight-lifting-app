import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F07 criterion 4: every repository contract the GRDB stores keep (`ExerciseRepositoryTests`,
/// `ProgramRepositoryTests`, `WorkoutRepositoryTests`, `StatsQueriesTests`, `WorkoutEventStoreTests`,
/// `SettingsRepositoryTests`) run against LedgerFakes' in-memory stores, each clause on a fresh store, so a fake
/// cannot drift from the real semantics (testing-strategy §2.2).
@Suite("In-memory stores · the repository contracts", .tags(.persistence), .timeLimit(.minutes(1)))
struct InMemoryContractTests {
    /// Linked stores over one empty state, the stats at `StatsQueriesContract.now`.
    static func history() -> HistoryStores {
        let stores = InMemoryStores(now: { StatsQueriesContract.now })
        return HistoryStores(workouts: stores.workouts, stats: stores.stats, programs: stores.programs)
    }

    @Test("InMemoryExerciseRepository keeps the contract clause", arguments: ExerciseRepositoryContract.clauses)
    func exercises_keepTheContract(_ clause: ExerciseRepositoryContract.Clause) async throws {
        let issue = try await clause.check(InMemoryExerciseRepository())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("InMemoryProgramRepository keeps the contract clause", arguments: ProgramRepositoryContract.clauses)
    func programs_keepTheContract(_ clause: ProgramRepositoryContract.Clause) async throws {
        let issue = try await clause.check(InMemoryProgramRepository())
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
