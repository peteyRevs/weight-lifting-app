import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8b, criteria 16, 27, 28 and 31: the switch, the program at the save and the discard, the replacement's
/// bests, and a superset member. The fixtures are `WorkoutStoreSwapTests`'.
@MainActor
@Suite("WorkoutStore swap, the program and the records", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSwapProgramTests {
    typealias Swap = WorkoutStoreSwapTests
    typealias Scene = WorkoutScene

    // MARK: Criteria 16 and 28: the switch, and the program at the save

    @Test("The switch opens on when the slot already carries a program change, and off turns it off (Q4)")
    func toggle_opensFromTheSlot() async throws {
        var running = try Fixtures.seedSession()
        let slot = try #require(running.exercises[0].slotID)
        running.programUpdates[slot] = Fixtures.CatalogID.overheadPress
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Swap.following(scene)
        let opened = try await Swap.open(store)
        #expect(opened.toggle?.isOn == true)
        store.send(.updateProgram(false))
        let row = try #require(store.swapSheet?.rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        #expect(await Swap.swaps(scene) == ["Dumbbell Bench Press false 15"])
        task.cancel()
    }

    @Test("Also update program lands with Save workout, and the history keeps the replacement")
    func toggle_landsWithTheSave() async throws {
        let scene = try await Scene.onHost(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        _ = try await Swap.open(store)
        store.send(.updateProgram(true))
        let row = try #require(store.swapSheet?.rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        let swapped = try #require(try await scene.session.current())
        store.send(.edit(.log(exerciseIndex: 0, setID: swapped.exercises[0].sets[0].id)))
        await store.drain()
        await eventually { store.shown?.doneSets == 1 }
        store.send(.finish)
        store.send(.save)
        await store.save()
        let program = try #require(try await scene.stores.programs.active())
        #expect(program.days[0].slots[0].exerciseID == row.id)
        let stored = try await scene.stores.workouts.workout(id: swapped.id)
        #expect(stored?.exercises[0].name == "Dumbbell Bench Press")
        #expect(store.receipt?.page.rows.first?.name == "Dumbbell Bench Press")
        task.cancel()
    }

    @Test("Discard leaves the program as it was, whatever the switch said")
    func toggle_notWithTheDiscard() async throws {
        let scene = try await Scene.onHost(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        _ = try await Swap.open(store)
        store.send(.updateProgram(true))
        let row = try #require(store.swapSheet?.rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        store.send(.finish)
        store.send(.discard)
        await store.discard()
        let program = try #require(try await scene.stores.programs.active())
        #expect(program.days[0].slots[0].exerciseID == Fixtures.CatalogID.benchPress)
        task.cancel()
    }

    // MARK: Criterion 27: the replacement's bests

    @Test("The replacement's bests are read once and merged: a record on it is felt once")
    func replacementBests_areReadOnce_recordFelt() async throws {
        let running = try Fixtures.seedSession()
        let catalog = try ExerciseCatalog.seed()
        let dumbbell = try #require(catalog.first { $0.name == "Dumbbell Bench Press" }).id
        // 15 lb × 5 beats the weight at five reps and not the estimate: one record.
        let bests = PersonalRecords.Bests(
            e1RM: [dumbbell: .pounds(100)],
            weightAtReps: [dumbbell: [Reps(clamping: 5): .pounds(10)]]
        )
        let haptics = FakeHaptics()
        let date = LockIsolated(Fixtures.now)
        let scene = try Scene.onFake(live: running)
        let stats = SwapStats(base: scene.stores.stats, bests: bests)
        let (store, task) = await Swap.following(scene) {
            $0.statsQueries = stats
            $0.haptics = haptics
            $0.date = DateGenerator { date.value }
        }
        await store.readBests()
        #expect(store.unreadBests.isEmpty)
        let row = try await #require(Swap.open(store).rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        await eventually { store.unreadBests == [dumbbell] }
        await store.readSwappedBests()
        await store.readSwappedBests()
        #expect(await stats.bestsAsked == [Set(running.exercises.map(\.exerciseID)), [dumbbell]])
        guard case let .loaded(merged) = store.bests else {
            Issue.record("the bests are known")
            return
        }
        #expect(merged.e1RM[dumbbell] == .pounds(100))

        let set = running.exercises[0].sets[0].id
        date.withValue { $0 += 10 }
        store.send(.edit(.log(exerciseIndex: 0, setID: set)))
        await store.drain()
        await eventually { store.shown?.doneSets == 1 }
        await giveWay()
        #expect(await haptics.played.count { $0 == .personalRecord } == 1)
        task.cancel()
    }

    @Test("A failed read of the replacement's bests is not retried, and no record is felt for it")
    func replacementBests_failedRead() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let stats = SwapStats(base: scene.stores.stats, bests: nil)
        let (store, task) = await Swap.following(scene) { $0.statsQueries = stats }
        store.bests = .loaded(PersonalRecords.Bests())
        store.bestsAsked = Set(running.exercises.map(\.exerciseID))
        let row = try await #require(Swap.open(store).rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        await eventually { !store.unreadBests.isEmpty }
        await store.readSwappedBests()
        #expect(store.unreadBests.isEmpty, "asked once, and not again")
        #expect(await stats.bestsAsked.count == 1)
        task.cancel()
    }

    // MARK: Criterion 31: a superset member

    @Test("A superset member is swapped alone: its superset flag and the block are unchanged")
    func supersetMember_isSwappedAlone() async throws {
        let running = try Fixtures.seedSession()
        let member = try #require(running.exercises.indices.last { running.exercises[$0].isSupersetWithPrevious })
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Swap.following(scene)
        store.send(.edit(.jump(exerciseIndex: member)))
        await store.drain()
        #expect(store.model.page?.card?.swap == "Swap exercise")
        let row = try await #require(Swap.open(store).rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        let live = try #require(try await scene.session.current())
        #expect(live.exercises[member].exerciseID == row.id)
        #expect(live.exercises[member].isSupersetWithPrevious)
        #expect(live.exercises[member - 1].exerciseID == running.exercises[member - 1].exerciseID)
        #expect(live.exercises[member].rest == running.exercises[member].rest)
        task.cancel()
    }
}

extension SwapSheetModel.Row {
    /// The choice the row's Use carries.
    var choice: SwapChoice {
        guard case let .swap(_, choice, _) = choose else {
            preconditionFailure("a row of the swap sheet chooses a swap")
        }
        return choice
    }
}
