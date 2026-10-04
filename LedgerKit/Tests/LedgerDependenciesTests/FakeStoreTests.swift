import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// What the fakes do beyond the contracts (S1 fix round 1): their streams keep only the newest value, as GRDB's
/// do (S1-SF2); an ended observation stops only itself (S1-N6); a refused materialisation writes no misses
/// (S1-N3); and a repository built on the catalog is seeded at its version (F7-8).
@Suite("Fake stores")
struct FakeStoreTests {
    @Test("A consumer that falls behind sees only the newest value, as GRDB's bridge delivers it")
    func slowConsumer_seesTheNewestOnly() async throws {
        let settings = InMemorySettingsRepository()
        var values = settings.observe().makeAsyncIterator()
        var later = Settings.default
        for seconds in [120, 150, 180] {
            later.defaultRest = RestDuration(seconds: seconds) ?? .defaultRest
            try await settings.save(later)
        }
        #expect(await values.next() == later)
    }

    @Test("Ending one observation early stops only it: writes go on, and a fresh observer sees them")
    func endedObservation_stopsOnlyItself() async throws {
        let stores = InMemoryStores()
        let history = try Fixtures.history(weeks: 2)
        let consumer = Task {
            var seen = 0
            for await _ in stores.workouts.observeRecent(limit: 5) {
                seen += 1
            }
            return seen
        }
        consumer.cancel()
        _ = await consumer.value
        try await stores.workouts.materialize(history[0], slotUpdates: [])
        var fresh = stores.workouts.observeRecent(limit: 5).makeAsyncIterator()
        #expect(await fresh.next() == [history[0]])
        try await stores.workouts.materialize(history[1], slotUpdates: [])
        #expect(await fresh.next() == [history[1], history[0]])
    }

    @Test("A materialisation that is refused writes none of its slot updates")
    func refusedMaterialisation_writesNoMisses() async throws {
        let stores = try InMemoryStores(
            seed: InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), programs: [Fixtures.seedProgram()])
        )
        var workout = try #require(Fixtures.history(weeks: 1).last)
        workout.name += "\u{0}"
        var slot = try #require(try await stores.programs.active()?.days[0].slots[0])
        slot.misses = [2]
        await #expect(throws: RepositoryError.nulInText("workout.name")) {
            try await stores.workouts.materialize(workout, slotUpdates: [slot])
        }
        #expect(try await stores.programs.active()?.days[0].slots[0].misses == [])
    }

    @Test("Built on the catalog, the exercise store is at the catalog's version: the launch's seed is a no-op")
    func catalogRepository_isSeededAtTheCatalogsVersion() async throws {
        let catalog = try ExerciseCatalog.seed()
        let exercises = InMemoryExerciseRepository(catalog: catalog)
        var renamed = catalog
        renamed[0].name += " (later)"
        try await exercises.seedIfNeeded(renamed, version: ExerciseCatalog.version)
        #expect(try await exercises.exercise(id: catalog[0].id) == catalog[0])
    }
}
