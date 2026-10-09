@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, criteria 2, 5 and 7: the cover's store, one test for each row S1 to S13 of the notes' table. It
/// follows the session's updates, so each test runs `follow()` in a task, as `WorkoutRoot` does, and waits
/// for what it expects by observing the store, never by time.
@MainActor
@Suite("WorkoutStore", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreTests {
    typealias Scene = WorkoutScene

    @Test("S1. The cover opens on the live workout as the session holds it")
    func follow_live_showsTheSessionsWorkout() async throws {
        let running = try WorkoutPreview.logged(6, in: Fixtures.seedSession())
        let scene = try Scene.onFake(live: running)
        let store = scene.store()
        #expect(store.model == .loading)
        #expect(store.shown == nil)

        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        let isTheSessions = store.shown == running
        #expect(isTheSessions)
        #expect(store.model.header?.title == "Upper A — Push focus")
        #expect(store.model.header?.progressValue == "Exercise 2 of 5")
        #expect(store.exit == nil)
        #expect(store.dialog == nil)
        task.cancel()
        await task.value
        #expect(store.shown != nil, "a cover that went away has not failed")
    }

    @Test("S2. Minimize closes the cover and leaves the workout live; nothing answers afterwards")
    func minimize_closesAndKeepsTheWorkoutLive() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.minimize)
        #expect(store.exit == .route(.minimized))
        #expect(store.model.header?.isEnabled == false)
        store.send(.finish)
        store.send(.discard)
        #expect(store.dialog == nil)
        #expect(store.discardAttempt == 0)
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
        task.cancel()
        await task.value

        // Asked again, the launcher's next cover shows the same workout.
        let (next, nextTask) = await scene.following()
        #expect(next.shown?.id == running.id)
        nextTask.cancel()
    }

    @Test("S3, S4. Finish asks; Keep lifting, or the dialog going away, returns to the workout")
    func finish_asks_keepLiftingReturns() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let unloaded = scene.store()
        unloaded.send(.finish)
        unloaded.send(.discard)
        #expect(unloaded.dialog == nil, "nothing to end before the workout is shown")
        #expect(unloaded.discardAttempt == 0)

        let (store, task) = await scene.following()
        store.send(.finish)
        #expect(store.dialog == .finish)
        store.send(.dismissFailure)
        #expect(store.dialog == .finish)
        store.send(.keepLifting)
        #expect(store.dialog == nil)
        #expect(store.exit == nil)
        #expect(await scene.asked() == [])
        task.cancel()
    }

    @Test("S8. A change made elsewhere is shown, and a dialog that is up stays up")
    func update_fromElsewhere_isShown() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.finish)
        let first = running.exercises[0].sets[0]
        try await scene.fake?.apply(.setLogged(
            exerciseIndex: 0, setID: first.id, weight: first.weight, reps: first.reps, doneAt: Fixtures.now
        ))
        await eventually { store.shown?.doneSets == 1 }
        #expect(store.dialog == .finish)
        #expect(store.exit == nil)
        task.cancel()
    }

    @Test(
        "S9, S10. A workout ended elsewhere closes the cover, whichever dialog was up, and says how it ended",
        arguments: [true, false], [WorkoutStore.Dialog?.none, .finish]
    )
    func endedElsewhere_closesTheCover(discarded: Bool, dialog: WorkoutStore.Dialog?) async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        if dialog == .finish {
            store.send(.finish)
        }
        #expect(store.dialog == dialog)
        if discarded {
            try await scene.fake?.discard(endedAt: Fixtures.now)
        } else {
            _ = try await scene.fake?.finish(endedAt: Fixtures.now)
        }
        await task.value
        #expect(store.exit == .route(discarded ? .discarded : .saved(running.id)))
        #expect(store.dialog == nil)
        store.send(.minimize)
        #expect(store.exit == .route(discarded ? .discarded : .saved(running.id)), "the first reason stands")
    }

    @Test("S11. A cover that opens with nothing live closes with nothing to tell the app")
    func follow_nothingLive_closesWithNoRoute() async throws {
        let scene = try Scene.onFake()
        let store = scene.store()
        await store.follow()
        #expect(store.exit == .nothingToShow)
        #expect(store.shown == nil)
        #expect(store.model == .loading)
    }

    @Test("S12. Updates that end, before or after a workout was shown, leave the failed screen, which closes")
    func follow_streamEnds_fails() async throws {
        for first in try [[], [WorkoutSessionUpdate(state: Fixtures.seedSession())]] {
            let scene = try Scene.on(EndedSession(first: first))
            let store = scene.store()
            await store.follow()
            #expect(store.model == .failed(WorkoutFailedModel(
                title: "Couldn't open this workout", message: "Close this screen and try again.", close: "Close"
            )))
            #expect(store.exit == nil)
            store.send(.finish)
            store.send(.discard)
            #expect(store.dialog == nil)
            #expect(store.discardAttempt == 0)
            store.send(.minimize)
            #expect(store.exit == .route(.minimized))
        }
    }
}

extension WorkoutStore {
    /// The workout on screen, when one is.
    var shown: WorkoutState? {
        guard case let .loaded(state) = workout else {
            return nil
        }
        return state
    }
}

extension WorkoutScreenModel {
    /// The header, when a workout is on screen.
    var header: WorkoutHeaderModel? {
        guard case let .workout(workout) = self else {
            return nil
        }
        return workout.header
    }
}
