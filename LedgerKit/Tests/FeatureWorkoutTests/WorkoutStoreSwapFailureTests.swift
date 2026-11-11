import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8b, criteria 22 to 26: a swap the session refuses, alternatives that cannot be read, nothing to offer,
/// a read that starts again, and a workout that ends under the sheet. The fixtures are `WorkoutStoreSwapTests`'.
@MainActor
@Suite("WorkoutStore swap failures", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSwapFailureTests {
    typealias Swap = WorkoutStoreSwapTests
    typealias Scene = WorkoutScene

    // MARK: Criteria 22 to 24 and 26: failures, nothing to offer, a read that starts again

    @Test("A swap the session refuses shows the change alert; the card and the program stay")
    func refusedSwap_isShown() async throws {
        let running = try Fixtures.seedSession()
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        let row = try await #require(Swap.open(store).rows.first)
        await scene.probe.fail(.append)
        store.send(.edit(.swap(exerciseIndex: 0, choice: row.choice, alsoUpdateProgram: true)))
        await store.drain()
        #expect(store.dialog == .editFailed)
        #expect(store.model.page?.card?.title == "Barbell Bench Press")
        let isUntouched = try await scene.holds(running)
        #expect(isUntouched)
        task.cancel()
    }

    @Test("Alternatives that cannot be read say so and offer nothing; opening again reads again")
    func failedRead_saysSo_reopenReadsAgain() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let exercises = SwapExercises(base: scene.stores.exercises, fails: true)
        let (store, task) = await Swap.following(scene) { $0.exerciseRepository = exercises }
        let failed = try await Swap.open(store)
        #expect(failed.message == "Couldn't load alternatives.")
        #expect(failed.rows.isEmpty && failed.toggle == nil)
        store.send(.cancelSwap)
        await exercises.heal()
        let healed = try await Swap.open(store)
        #expect(healed.rows.count == 8)
        #expect(await exercises.catalogReads == 2)
        task.cancel()
    }

    @Test("A last session that cannot be read fails the whole read: no load is guessed")
    func failedLastRead_offersNothing() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let stats = SwapStats(base: scene.stores.stats, failsLast: true)
        let (store, task) = await Swap.following(scene) { $0.statsQueries = stats }
        let sheet = try await Swap.open(store)
        #expect(sheet.message == "Couldn't load alternatives.")
        #expect(sheet.rows.isEmpty)
        task.cancel()
    }

    @Test("An exercise no longer stored offers nothing, and says so, with no switch")
    func notStored_noAlternatives() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let exercises = SwapExercises(base: scene.stores.exercises, holdsTheExercise: false)
        let (store, task) = await Swap.following(scene) { $0.exerciseRepository = exercises }
        let sheet = try await Swap.open(store)
        #expect(sheet.message == "No alternatives for this exercise.")
        #expect(sheet.rows.isEmpty && sheet.toggle == nil)
        task.cancel()
    }

    @Test("An earlier attempt's answer is dropped: the sheet opened again shows only its own read")
    func staleAttempt_isDropped() async throws {
        let gate = Gate()
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let exercises = SwapExercises(base: scene.stores.exercises, gate: gate)
        let (store, task) = await Swap.following(scene) { $0.exerciseRepository = exercises }
        store.send(.openSwap)
        let stale = Task { await store.loadSwap() }
        await gate.waitForArrival()
        store.send(.cancelSwap)
        store.send(.openSwap)
        await gate.open()
        await stale.value
        #expect(store.swapSheet?.rows.isEmpty == true, "the first attempt's answer is not shown")
        await store.loadSwap()
        #expect(store.swapSheet?.rows.count == 8)
        task.cancel()
    }

    @Test("A read whose task starts again reads again, and the rows are shown once")
    func restartedRead_showsOnce() async throws {
        let gate = Gate()
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let exercises = SwapExercises(base: scene.stores.exercises, gate: gate)
        let (store, task) = await Swap.following(scene) { $0.exerciseRepository = exercises }
        store.send(.openSwap)
        let first = Task { await store.loadSwap() }
        await gate.waitForArrival()
        first.cancel()
        let second = Task { await store.loadSwap() }
        await gate.open()
        await first.value
        await second.value
        #expect(await exercises.catalogReads == 2)
        #expect(store.swapSheet?.rows.count == 8)
        task.cancel()
    }

    // MARK: Criterion 25: the workout moves or ends under the sheet

    @Test("An offered exercise put into the workout elsewhere takes the sheet down; its row then does nothing")
    func offeredExerciseTakenElsewhere_closesTheSheet() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await Swap.following(scene)
        let row = try await #require(Swap.open(store).rows.first)
        try await scene.fake?.apply(.exerciseSwapped(
            exerciseIndex: 3, exerciseID: row.id, name: row.name, alsoUpdateProgram: false
        ))
        await eventually { store.dialog == nil }
        store.send(.edit(row.choose))
        await store.drain()
        #expect(await Swap.swaps(scene).count == 1, "only the other hand's swap")
        #expect(store.model.page?.card?.title == "Barbell Bench Press")
        task.cancel()
    }

    @Test("A workout ended elsewhere closes the sheet and the cover")
    func endedElsewhere_closesBoth() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await Swap.following(scene)
        _ = try await Swap.open(store)
        try await scene.session.discard(endedAt: Fixtures.now)
        await eventually { store.exit != nil }
        #expect(store.dialog == nil)
        #expect(store.exit == .route(.discarded))
        await task.value
    }
}
