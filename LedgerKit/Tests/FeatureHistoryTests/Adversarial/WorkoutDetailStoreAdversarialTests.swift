import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S2 adversarial (G2): a past workout's detail store against its sources and its delete, where
/// `WorkoutDetailStoreTests` is silent. A confirmation during a delete in flight; a delete whose task is cancelled or
/// run twice (the root's `.task(id: deletion)` re-runs when the view comes back); the observation's nil arriving
/// before the delete returns; a delete elsewhere seen by several details of one workout and one of another; a row's
/// route overtaken by the close; and a failed delete followed by a delete elsewhere. The settings' side:
/// `WorkoutDetailSettingsAdversarialTests`.
@MainActor
@Suite("Adversarial F13 S2 · the detail's store", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutDetailStoreAdversarialTests {
    static let twelve = HistoryFixtures.twelve()
    static let newest = twelve[11]

    static var isLoaded: (WorkoutDetailStore) -> Bool {
        { store in
            if case .loaded = store.state {
                return true
            }
            return false
        }
    }

    // MARK: - Delete once

    @Test("A confirmation while a delete is in flight is dropped, and the repository is asked once")
    func confirmDuringDelete_isDropped() async throws {
        let scene = GatedDetailScene(Self.newest.id, gate: .before)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.confirmDelete()
        let deleting = Task { await scene.store.delete() }
        try #require(await settles { scene.workouts.isWaiting })
        scene.store.confirmDelete()
        scene.store.confirmDelete()
        #expect(scene.store.deletion == 1)
        scene.workouts.open()
        await deleting.value
        #expect(scene.workouts.deleteCount == 1)
        #expect(scene.store.state == .gone)
        #expect(!scene.store.showsDeleteFailure)
    }

    /// F13-S2-3: a second run of the root's `.task(id: deletion)` while the first is in flight (the view gone and back
    /// within the write) does not ask the repository again (fixed in round 1).
    @Test("F13-S2-3: the delete task run again while its first run is in flight deletes once")
    func deleteRunTwice_whileInFlight_deletesOnce() async throws {
        let scene = GatedDetailScene(Self.newest.id, gate: .before)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.confirmDelete()
        let first = Task { await scene.store.delete() }
        try #require(await settles { scene.workouts.isWaiting })
        let second = Task { await scene.store.delete() }
        // The second run reaches the repository at once, or returns at once: either way it is done or waiting.
        _ = await settles { scene.workouts.deleteCount == 2 }
        scene.workouts.open()
        scene.workouts.open()
        await first.value
        await second.value
        let deletedOnce = scene.workouts.deleteCount == 1
        #expect(deletedOnce)
    }

    /// F13-S2-3: the delete's task is the view's, so it is cancelled when the view goes (a tab switch, a back swipe)
    /// before the write starts. The confirmation stays pending, and the same task run again when the view comes back
    /// (same `deletion`) performs it (fixed in round 1).
    @Test("F13-S2-3: a confirmed delete cancelled before its write is not lost silently")
    func deleteCancelled_isNotLostSilently() async throws {
        let scene = GatedDetailScene(Self.newest.id, gate: .before)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.confirmDelete()
        let deleting = Task { await scene.store.delete() }
        try #require(await settles { scene.workouts.isWaiting })
        deleting.cancel()
        await deleting.value
        #expect(!scene.store.showsDeleteFailure, "nothing is said")
        // The view is back: the root's `.task(id: deletion)` runs again with the same number.
        scene.workouts.open()
        await scene.store.delete()
        let stored = try await scene.memory.workouts.workout(id: Self.newest.id)
        let isDeletedOrSaid = stored == nil || scene.store.showsDeleteFailure
        #expect(isDeletedOrSaid)
        #expect(stored == nil, "the pending delete ran")
    }

    @Test("The observation's nil before the delete returns: the detail is gone, every route handed is its close")
    func nilBeforeDeleteReturns_closesOnly() async {
        let scene = GatedDetailScene(Self.newest.id, gate: .after)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.confirmDelete()
        let deleting = Task { await scene.store.delete() }
        await eventually { scene.store.state == .gone && scene.store.pendingRoute != nil }
        var handed: [HistoryRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.workouts.open()
        await deleting.value
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed.allSatisfy { $0 == .closeWorkout(Self.newest.id) })
        // Two closes reach the app when the first is taken before the delete returns; the router pops only a
        // `.workout(id)` on top, so the second pops nothing once the first has popped (HistoryRoutesAdversarialTests).
        #expect(handed.count == 2)
        #expect(scene.workouts.deleteCount == 1)
        #expect(!scene.store.showsDeleteFailure)
    }

    // MARK: - A delete elsewhere

    @Test("A delete elsewhere closes every detail of that workout, once each, and no detail of another")
    func deleteElsewhere_closesOnlyItsDetails() async throws {
        let memory = InMemoryStores(seed: InMemoryStores.Seed(workouts: Self.twelve, settings: Fixtures.settingsLb))
        func detail(_ id: WorkoutID) -> WorkoutDetailStore {
            withTestDependencies {
                $0.workoutRepository = memory.workouts
                $0.settingsRepository = memory.settings
            } operation: {
                WorkoutDetailStore(workout: id)
            }
        }
        let other = Self.twelve[10]
        let stores = [detail(Self.newest.id), detail(Self.newest.id), detail(other.id)]
        let runs = stores.map { store in Task { await store.run() } }
        defer { runs.forEach { $0.cancel() } }
        await eventually { stores.allSatisfy(Self.isLoaded) }
        try await memory.workouts.delete(id: Self.newest.id)
        await eventually { stores[0].state == .gone && stores[1].state == .gone }
        for store in stores.prefix(2) {
            var handed: [HistoryRoute] = []
            store.deliverRoute { handed.append($0) }
            store.deliverRoute { handed.append($0) }
            #expect(handed == [.closeWorkout(Self.newest.id)])
        }
        let otherKept = Self.isLoaded(stores[2]) && stores[2].pendingRoute == nil
        #expect(otherKept)
    }

    @Test("A row's route still waiting when the workout goes is replaced by the close")
    func pendingRowRoute_thenDeletedElsewhere_isTheClose() async throws {
        let scene = GatedDetailScene(Self.newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.send(.exercise(HistoryFixtures.bench.id))
        try await scene.memory.workouts.delete(id: Self.newest.id)
        await eventually { scene.store.state == .gone }
        var handed: [HistoryRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.closeWorkout(Self.newest.id)])
        scene.store.send(.exercise(HistoryFixtures.bench.id))
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed.count == 2, "a tap on what is left (the ground) can still be sent: \(handed)")
    }

    @Test("A failed delete, then the workout deleted elsewhere: the detail closes")
    func failedDelete_thenDeletedElsewhere_closes() async throws {
        let scene = DetailScene(Self.newest.id, failsDeletes: true)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.confirmDelete()
        await scene.store.delete()
        #expect(scene.store.showsDeleteFailure)
        try await scene.memory.workouts.delete(id: Self.newest.id)
        await eventually { scene.store.state == .gone }
        #expect(scene.store.pendingRoute?.route == .closeWorkout(Self.newest.id))
    }
}
