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
        return HistoryStores(
            workouts: stores.workouts,
            stats: stores.stats,
            programs: stores.programs,
            events: stores.events
        )
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

    @Test(
        "The linked InMemoryWorkoutRepository keeps the linked clause",
        arguments: WorkoutRepositoryContract.linkedClauses
    )
    func workouts_keepTheLinkedClauses(_ clause: WorkoutRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Self.history())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test(
        "InMemoryWorkoutRepository keeps the History list's clause (F13 S1)",
        arguments: WorkoutRepositoryContract.historyClauses
    )
    func workouts_keepTheHistoryClauses(_ clause: WorkoutRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Self.history())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test(
        "InMemoryWorkoutRepository keeps the workout detail's clause (F13 S2)",
        arguments: WorkoutRepositoryContract.detailClauses
    )
    func workouts_keepTheDetailClauses(_ clause: WorkoutRepositoryContract.Clause) async throws {
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

    @Test("Without an exercise store, a program store checks no slot's exercise")
    func unlinkedPrograms_checkNoExercise() async throws {
        let program = try ProgramRepositoryContract.program()
        let unlinked = InMemoryProgramRepository()
        try await unlinked.save(program)
        #expect(try await unlinked.active() == program)
    }

    @Test("Without an event store, a workout store saves, drops no log and says so; its programs check no exercise")
    func unlinkedWorkouts_holdNoLog() async throws {
        let program = try ProgramRepositoryContract.program()
        let programs = InMemoryProgramRepository(programs: [program])
        let unlinked = InMemoryWorkoutRepository(programs: programs)
        let events = InMemoryWorkoutEventStore()
        var workout = WorkoutRepositoryContract.workout()
        workout.source = WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: program.days[0].id)
        let unknown = ExerciseID(EventBuilders.uuid(0x404))
        workout.programUpdates = [program.days[0].slots[0].id: unknown]
        _ = try await events.append(EventBuilders.log(from: [.restSkipped], workoutID: workout.id))
        let dropped = try await unlinked.materialize(workout, slotUpdates: [], droppingLog: true)
        #expect(!dropped)
        #expect(await events.uncompactedWorkoutIDs() == [workout.id])
        #expect(try await unlinked.recent(limit: 5).map(\.id) == [workout.id])
        #expect(try await programs.active()?.days[0].slots[0].exerciseID == unknown)
    }

    @Test("A seed is stored as given; one whose programs name exercises its catalog lacks reports them (F7-10)")
    func seeds_holdOnlyWhatADatabaseCould() async throws {
        let program = try ProgramRepositoryContract.program()
        let legal = InMemoryStores(seed: InMemoryStores.Seed(
            catalog: ProgramRepositoryContract.exercises,
            programs: [program]
        ))
        #expect(try await legal.programs.active() == program)
        try await legal.programs.save(program)
        let missing = ProgramRepositoryContract.exercises[5].id
        withKnownIssue {
            _ = InMemoryStores(seed: InMemoryStores.Seed(
                catalog: Array(ProgramRepositoryContract.exercises.prefix(5)),
                programs: [program]
            ))
        } matching: { issue in
            issue.description.contains(missing.rawValue.uuidString)
        }
    }
}
