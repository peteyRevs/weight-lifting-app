import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F07 S1 close-out: the fix round's linked stores and per-query date (decisions 4 and 6) as a feature test meets
/// them.
@Suite("Adversarial F07 S1 close-out · linked stores and the stats' date", .timeLimit(.minutes(1)))
struct StoresCloseoutAdversarialTests {
    @Test("F7-10: a program seeded without the catalog can be saved back unchanged, as no database could refuse it")
    func seededProgram_savesBackUnchanged() async throws {
        let program = try Fixtures.seedProgram()
        let stores = InMemoryStores(seed: InMemoryStores.Seed(programs: [program]))
        #expect(try await stores.programs.active() == program)
        // A database holding this program holds its exercises (the slots' foreign key), so saving it back
        // unchanged succeeds there. The fake holds a state no database can, then refuses its own program.
        await #expect(throws: Never.self) { try await stores.programs.save(program) }
    }

    @Test("F7-11: the stats of stores bound by withTestDependencies answer after the operation, as before the fix")
    func statsAfterTheOperation_needNoDependency() async throws {
        let workout = try #require(Fixtures.history(weeks: 1).last)
        var bound: InMemoryStores?
        try await withTestDependencies {
            bound = $0.inMemoryStores()
        } operation: {
            @Dependency(\.workoutRepository) var workouts
            try await workouts.materialize(workout, slotUpdates: [])
        }
        let stores = try #require(bound)
        let calendar = try WeekCalendar(
            startDate: Fixtures.seedProgram().startDate,
            weekStart: .monday,
            calendar: Fixtures.calendar
        )
        // Outside the operation the `date` dependency is the library's test value, which records an issue:
        // the stats should keep the date they were bound under (Fixtures.now) rather than fail the test.
        let byWeek = try await stores.stats.e1RMByWeek(
            exerciseID: Fixtures.CatalogID.benchPress,
            lastWeeks: 1,
            calendar: calendar
        )
        #expect(!byWeek.isEmpty)
    }

    @Test("Inside the operation the stats follow the date the test set, before or after binding (F7-6 fixed)")
    func statsDate_followsTheOperationsDate() async throws {
        let workout = try #require(Fixtures.history(weeks: 1).last)
        let calendar = try WeekCalendar(
            startDate: Fixtures.seedProgram().startDate,
            weekStart: .monday,
            calendar: Fixtures.calendar
        )
        try await withTestDependencies {
            $0.date = .constant(Fixtures.now.addingTimeInterval(14 * 86400))
            $0.inMemoryStores()
        } operation: {
            @Dependency(\.workoutRepository) var workouts
            @Dependency(\.statsQueries) var stats
            try await workouts.materialize(workout, slotUpdates: [])
            let later = try await stats.e1RMByWeek(
                exerciseID: Fixtures.CatalogID.benchPress, lastWeeks: 1, calendar: calendar
            )
            let now = try await withDependencies {
                $0.date = .constant(Fixtures.now)
            } operation: {
                try await stats.e1RMByWeek(exerciseID: Fixtures.CatalogID.benchPress, lastWeeks: 1, calendar: calendar)
            }
            #expect(later.isEmpty && !now.isEmpty)
        }
    }
}
