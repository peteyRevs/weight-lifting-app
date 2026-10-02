import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 risk "seeding time on the watch": seeding a 214-entry catalog into a new database file takes under
/// `PerformanceBudget.catalogSeed` (300 ms; above it, F07 seeds after the first frame), and a search over the
/// seeded rows under `PerformanceBudget.exerciseSearch` (F12: 10 ms a keystroke). Timings are only meaningful
/// without other suites competing for the CPU, so this is `.performance`, nightly only (testing-strategy §6);
/// the figure that matters comes from the `Nightly-Watch` plan, run by hand with
/// `-only-testing:LedgerPersistenceTests/CatalogTimingTests`. Each median also goes into the result bundle.
@Suite(
    "GRDBExerciseRepository · catalog timing",
    .tags(.persistence, .performance),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only")
)
struct CatalogTimingTests {
    static let catalog = Seeders.catalog(count: 214, version: 1)

    @Test("Seeding 214 entries into a new database file takes under 300 ms (median of 5)")
    func seed214_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let clock = ContinuousClock()
        var all: [Duration] = []
        for run in 0 ... PerformanceBudget.runs {
            let queue = try LedgerDatabase.open(at: directory.file("run-\(run)/ledger.sqlite"))
            let repository = GRDBExerciseRepository(queue, now: { EventBuilders.start })
            try await all.append(clock.measure {
                try await repository.seedIfNeeded(Self.catalog.exercises, version: Self.catalog.version)
            })
            #expect(try await repository.all().count == 214)
        }
        let median = Self.median(of: all, named: "catalog-seed.txt")
        #expect(median < PerformanceBudget.catalogSeed, "median \(median); runs \(all)")
    }

    @Test("Searching 214 seeded entries plus custom ones takes under 10 ms (median of 5)")
    func search214_underBudget() async throws {
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory(), now: { EventBuilders.start })
        try await repository.seedIfNeeded(Self.catalog.exercises, version: Self.catalog.version)
        for exercise in ExerciseRepositoryContract.searchable {
            try await repository.save(exercise)
        }
        let clock = ContinuousClock()
        var all: [Duration] = []
        for _ in 0 ... PerformanceBudget.runs {
            try await all.append(clock.measure {
                _ = try await repository.search("press", equipment: nil, muscle: nil)
            })
        }
        let median = Self.median(of: all, named: "exercise-search.txt")
        #expect(median < PerformanceBudget.exerciseSearch, "median \(median); runs \(all)")
    }

    /// The median of `all` after its first (warm-up) run, recorded in the result bundle as `name`.
    static func median(of all: [Duration], named name: String) -> Duration {
        let timings = all.dropFirst().sorted()
        let median = timings[timings.startIndex + timings.count / 2]
        Attachment.record("median \(median); warm-up \(all[0]); runs \(timings)", named: name)
        return median
    }
}
