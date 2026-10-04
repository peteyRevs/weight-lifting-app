import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F07 S1 adversarial round 1: LedgerFakes' fixtures and preview seed through the real database. `FixturesTests`
/// saves them to the fakes, which check no foreign key; here they go where the app will put them: a database
/// seeded with the bundled catalog, and the GRDB stores must then answer as the preview's fakes do.
@Suite("Adversarial F07 S1 · fixtures in the database", .tags(.persistence))
struct FixturesDatabaseAdversarialTests {
    struct Database {
        let queue: DatabaseQueue
        let exercises: GRDBExerciseRepository
        let programs: GRDBProgramRepository
        let workouts: GRDBWorkoutRepository
        let stats: GRDBStatsQueries
        let settings: GRDBSettingsRepository
    }

    /// A database holding `seed` as the app's launch would write it: the catalog seeded, then the programs, the
    /// workouts and the settings saved.
    static func database(_ seed: InMemoryStores.Seed) async throws -> Database {
        let queue = try LedgerDatabase.inMemory()
        let database = Database(
            queue: queue,
            exercises: GRDBExerciseRepository(queue, now: { Fixtures.now }),
            programs: GRDBProgramRepository(queue, now: { Fixtures.now }),
            workouts: GRDBWorkoutRepository(queue, now: { Fixtures.now }),
            stats: GRDBStatsQueries(queue, now: { Fixtures.now }),
            settings: GRDBSettingsRepository(queue, now: { Fixtures.now })
        )
        try await database.exercises.seedIfNeeded(seed.catalog, version: seed.catalogVersion)
        for program in seed.programs {
            try await database.programs.save(program)
        }
        for workout in seed.workouts {
            try await database.workouts.materialize(workout, slotUpdates: [])
        }
        try await database.settings.save(seed.settings)
        return database
    }

    @Test("The preview seed stores whole in a real database: every slot names a catalog exercise")
    func previewSeed_storesInTheDatabase() async throws {
        let seed = try InMemoryStores.Seed.preview()
        let database = try await Self.database(seed)
        #expect(try await database.exercises.all().count == seed.catalog.count)
        #expect(try await database.programs.active() == Fixtures.seedProgram())
        #expect(try await database.workouts.recent(limit: 100).count == seed.workouts.count)
        #expect(try await database.settings.load() == seed.settings)
    }

    /// The per-exercise stats queries, spelled (a dictionary is sorted first).
    static func stats(
        _ stats: any StatsQueries,
        _ exercise: ExerciseID,
        _ calendar: WeekCalendar
    ) async throws -> [String] {
        let byWeek = try await stats.e1RMByWeek(exerciseID: exercise, lastWeeks: 8, calendar: calendar)
        return try await [
            "last \(String(describing: stats.lastPerformance(exerciseID: exercise)))",
            "best \(String(describing: stats.bestE1RM(exerciseID: exercise)))",
            "records \(stats.personalRecords(exerciseID: exercise))",
            "byWeek \(byWeek.sorted { $0.key < $1.key })",
            "sessions \(stats.sessionCount(exerciseID: exercise))"
        ]
    }

    @Test("The preview's fakes answer every read and stats query as the database holding the same seed does")
    func previewSeed_fakesMatchTheDatabase() async throws {
        let seed = try InMemoryStores.Seed.preview()
        let database = try await Self.database(seed)
        let fakes = InMemoryStores(seed: seed)
        #expect(try await database.exercises.all() == fakes.exercises.all())
        #expect(try await database.workouts.recent(limit: 100) == fakes.workouts.recent(limit: 100))
        let calendar = try WeekCalendar(
            startDate: Fixtures.seedProgram().startDate,
            weekStart: .monday,
            calendar: Fixtures.calendar
        )
        let week = calendar.week(containing: Fixtures.now)
        for exercise in try Fixtures.seedProgram().days.flatMap(\.slots).map(\.exerciseID) {
            let actual = try await Self.stats(database.stats, exercise, calendar)
            let wanted = try await Self.stats(fakes.stats, exercise, calendar)
            #expect(actual == wanted, "\(exercise)")
        }
        #expect(try await database.stats.weeklyVolume(in: week) == fakes.stats.weeklyVolume(in: week))
        #expect(try await database.stats.sessionsCompleted(in: week) == fakes.stats.sessionsCompleted(in: week))
        #expect(try await database.stats.recentlyLogged(limit: 20) == fakes.stats.recentlyLogged(limit: 20))
    }

    @Test("The seed session, finished, materialises into the database with the seed program's slot updates")
    func seedSession_materialisesWithSlotUpdates() async throws {
        let database = try await Self.database(InMemoryStores.Seed(catalog: ExerciseCatalog.seed()))
        let program = try Fixtures.seedProgram()
        try await database.programs.save(program)
        var session = try Fixtures.seedSession()
        session.phase = .finished
        session.endedAt = Fixtures.now.addingTimeInterval(3600)
        let slots = try program.days[0].slots.map { try $0.with(misses: [4]) }
        try await database.workouts.materialize(session, slotUpdates: slots)
        #expect(try await database.workouts.workout(id: Fixtures.sessionID)?.id == Fixtures.sessionID)
        #expect(try await database.programs.active()?.days[0].slots.map(\.misses) == slots.map(\.misses))
    }

    @Test("A long history (60 weeks) keeps every id distinct and stores whole", arguments: [20, 60])
    func longHistory_storesWhole(weeks: Int) async throws {
        let history = try Fixtures.history(weeks: weeks)
        let sets = history.flatMap(\.exercises).flatMap(\.sets).map(\.id)
        let rows = history.flatMap(\.exercises).map(\.id)
        #expect(Set(sets).count == sets.count && Set(rows).count == rows.count)
        #expect(try history == (Fixtures.history(weeks: weeks)), "deterministic")
        let database = try await Self.database(InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), workouts: history))
        #expect(try await database.workouts.recent(limit: 1000).count == history.count)
        #expect(try await InMemoryWorkoutRepository(workouts: history).recent(limit: 1000).count == history.count)
    }
}
