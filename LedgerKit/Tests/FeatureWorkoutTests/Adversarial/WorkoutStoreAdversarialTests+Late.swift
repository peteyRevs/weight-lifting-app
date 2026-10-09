@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Taps and updates that arrive late, and a cover built again.
extension WorkoutStoreAdversarialTests {
    @Test(
        "A discard that loses to a finish elsewhere is no failure: the cover closes as saved",
        arguments: World.Kind.allCases
    )
    func discard_losesToFinishElsewhere_closesAsSaved(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            let live = followed.live
            defer { task.cancel() }
            await world.session.hold(.discard)
            store.send(.finish)
            store.send(.discard)
            let running = Task { await store.discard() }
            await world.session.waitUntilHeld()
            _ = try await world.truth.finish(endedAt: Fixtures.now.addingTimeInterval(5))
            await world.session.release()
            await running.value
            await eventually("the cover to close") { store.exit != nil }
            #expect(store.exit == .route(.saved(live.id)))
            #expect(store.dialog == nil)
        }
    }

    @Test(
        "L23 under \"End workout?\": the workout ends elsewhere; the dialog goes and a late tap does nothing",
        arguments: World.Kind.allCases
    )
    func endedUnderTheFinishDialog_lateTapsDoNothing(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            let live = followed.live
            defer { task.cancel() }
            store.send(.finish)
            #expect(store.dialog == .finish)
            _ = try await world.truth.finish(endedAt: Fixtures.now.addingTimeInterval(5))
            await eventually("the cover to close") { store.exit != nil }
            #expect(store.exit == .route(.saved(live.id)))
            #expect(store.dialog == nil)

            // Day 1 starts elsewhere; the stale dialog's "Discard" must not reach it.
            let second = try await world.begin(day: 1)
            let attempts = store.discardAttempt
            store.send(.discard)
            store.send(.minimize)
            store.send(.finish)
            await store.discard()
            await giveWay()
            #expect(store.discardAttempt == attempts)
            #expect(await world.session.count(.discard) == 0)
            #expect(store.exit == .route(.saved(live.id)), "the exit is set once")
            #expect(store.dialog == nil)
            #expect(try await world.live()?.id == second.id)
        }
    }

    @Test(
        "\"Discard\" with no dialog showing, and before the first update, does nothing",
        arguments: World.Kind.allCases
    )
    func discard_beforeAnything_doesNothing(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let live = try await world.begin(day: 0)
            let store = WorkoutStore()
            store.send(.discard)
            store.send(.finish)
            await store.discard()
            #expect(store.dialog == nil)
            #expect(await world.session.count(.discard) == 0)
            #expect(try await unchanged(world.live(), live))
        }
    }

    @Test("The discard ends the workout at the injected date")
    func discard_endsAtTheInjectedDate() async throws {
        try await World.run(.fake) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            defer { task.cancel() }
            world.clock.setValue(Fixtures.now.addingTimeInterval(777))
            store.send(.finish)
            store.send(.discard)
            await store.discard()
            let fake = try #require(world.truth as? FakeWorkoutSessionClient)
            #expect(await fake.applied.last == .discarded(endedAt: Fixtures.now.addingTimeInterval(777)))
        }
    }

    @Test("A cover rebuilt after its task was cancelled follows the same session again", arguments: World.Kind.allCases)
    func followAgain_afterCancel_stillFollows(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            let live = followed.live
            task.cancel()
            await task.value
            #expect(store.exit == nil, "a cancelled task is not an ended workout")
            let set = try #require(live.exercises.first?.sets.first)
            let next = try await world.truth.apply(
                .setLogged(exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: Fixtures.now)
            )
            // The same view appearing again runs its task again, on the store it kept.
            let again = Task { await store.follow() }
            defer { again.cancel() }
            await eventually("the store to follow again after its task was restarted") { store.onScreen == next }
        }
    }
}
