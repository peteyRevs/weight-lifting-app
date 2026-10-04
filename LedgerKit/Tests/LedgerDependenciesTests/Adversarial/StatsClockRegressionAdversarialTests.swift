import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F07 S1 fix round 2 verification: the stats clock of `inMemoryStores` (F7-11) and the seed check (F7-10) in the
/// shapes a store test can take: two stores bound in one `configure`, nested `withTestDependencies`, stores bound
/// by a plain `withDependencies`, stores kept from one scope and queried in another, and the preview seed.
@Suite("Adversarial F07 S1 fix round 2 · stats clock and seeds", .timeLimit(.minutes(1)))
struct StatsClockRegressionAdversarialTests {
    static let later = Fixtures.now.addingTimeInterval(14 * 86400)

    /// Whether the stats call the week of `Fixtures.history(weeks: 1).last` (Monday of `Fixtures.now`'s week) current.
    static func seesThisWeek(_ stores: InMemoryStores) async throws -> Bool {
        let calendar = try WeekCalendar(
            startDate: Fixtures.seedProgram().startDate,
            weekStart: .monday,
            calendar: Fixtures.calendar
        )
        let byWeek = try await stores.stats.e1RMByWeek(
            exerciseID: Fixtures.CatalogID.benchPress,
            lastWeeks: 1,
            calendar: calendar
        )
        return !byWeek.isEmpty
    }

    static func materialiseLastWorkout(_ stores: InMemoryStores) async throws {
        let workout = try #require(Fixtures.history(weeks: 1).last)
        try await stores.workouts.materialize(workout, slotUpdates: [])
    }

    @Test("Two stores bound in one configure both answer, after the operation, with the date configure ended with")
    func twoStores_bothKeepTheConfiguredDate() async throws {
        var first: InMemoryStores?
        var second: InMemoryStores?
        try await withTestDependencies {
            first = $0.inMemoryStores()
            second = $0.inMemoryStores()
            $0.date = .constant(Self.later)
        } operation: {
            for stores in [first, second].compactMap(\.self) {
                try await Self.materialiseLastWorkout(stores)
                let sees = try await Self.seesThisWeek(stores)
                #expect(!sees)
            }
        }
        for stores in [first, second].compactMap(\.self) {
            let sees = try await Self.seesThisWeek(stores)
            #expect(!sees, "after the operation: the configured later date")
        }
    }

    @Test("Stores of an outer withTestDependencies keep the outer configured date after both operations")
    func nested_outerStoresKeepTheirDate() async throws {
        var outer: InMemoryStores?
        try await withTestDependencies {
            outer = $0.inMemoryStores()
            $0.date = .constant(Self.later)
        } operation: {
            let stores = try #require(outer)
            try await Self.materialiseLastWorkout(stores)
            let inner: Bool = try await withTestDependencies {
                $0.inMemoryStores()
            } operation: { () async throws -> Bool in
                // Inside the inner operation the current `date` is the inner default, Fixtures.now.
                try await Self.seesThisWeek(stores)
            }
            #expect(inner)
            let afterInner = try await Self.seesThisWeek(stores)
            #expect(!afterInner)
        }
        let afterBoth = try await Self.seesThisWeek(#require(outer))
        #expect(!afterBoth)
    }

    @Test("Stores bound by a plain withDependencies keep the date at binding and need no dependency afterwards")
    func plainWithDependencies_keepsTheBindingDate() async throws {
        var bound: InMemoryStores?
        withDependencies {
            $0.date = .constant(Fixtures.now)
            bound = $0.inMemoryStores()
        } operation: {}
        let stores = try #require(bound)
        try await Self.materialiseLastWorkout(stores)
        let sees = try await Self.seesThisWeek(stores)
        #expect(sees)
    }

    @Test("The synchronous withTestDependencies binds kept stores to the date its configure ended with, too")
    func synchronousOverload_keepsTheConfiguredDate() async throws {
        var kept: InMemoryStores?
        withTestDependencies {
            kept = $0.inMemoryStores()
            $0.date = .constant(Self.later)
        } operation: {}
        let stores = try #require(kept)
        try await Self.materialiseLastWorkout(stores)
        let sees = try await Self.seesThisWeek(stores)
        #expect(!sees)
    }

    @Test("A legal seed reports nothing: the preview seed, and programs with exactly their exercises")
    func legalSeeds_reportNothing() throws {
        _ = try InMemoryStores(seed: .preview())
        let program = try Fixtures.seedProgram()
        let catalog = try ExerciseCatalog.seed()
        let named = Set(program.days.flatMap(\.slots).map(\.exerciseID))
        let exact = InMemoryStores.Seed(catalog: catalog.filter { named.contains($0.id) }, programs: [program])
        #expect(exact.missingExercises.isEmpty)
        _ = InMemoryStores(seed: exact)
    }

    @Test("An illegal seed names every exercise it lacks, once each")
    func illegalSeed_namesEveryMissingExercise() throws {
        let program = try Fixtures.seedProgram()
        let catalog = try ExerciseCatalog.seed().filter { $0.id != Fixtures.CatalogID.benchPress }
        let seed = InMemoryStores.Seed(catalog: catalog, programs: [program, program])
        #expect(seed.missingExercises == [Fixtures.CatalogID.benchPress])
        withKnownIssue {
            _ = InMemoryStores(seed: seed)
        } matching: { issue in
            issue.description.contains(Fixtures.CatalogID.benchPress.rawValue.uuidString)
        }
    }
}
