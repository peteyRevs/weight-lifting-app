@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, criterion 5: "Finish" can only discard for now. Rows S5 to S7 and S13 of the notes' table: the
/// discard goes through the session, once; a refusal is shown and the workout stays; nothing else is a
/// failure.
@MainActor
@Suite("WorkoutStore discard", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreDiscardTests {
    typealias Scene = WorkoutScene

    @Test("S5. Discard ends the workout through the session, once, and closes the cover with nothing live")
    func discard_endsTheWorkoutAndCloses() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.finish)
        store.send(.discard)
        store.send(.discard)
        #expect(store.dialog == nil)
        #expect(store.isDiscarding)
        #expect(store.discardAttempt == 1)
        #expect(store.model.header?.isEnabled == false)
        store.send(.minimize)
        #expect(store.exit == nil, "nothing answers while the discard runs")

        await store.discard()
        await store.discard()
        #expect(store.exit == .route(.discarded))
        #expect(try await scene.session.current()?.id == nil)
        #expect(await scene.asked() == [.discarded(Fixtures.now)])
        #expect(try await scene.stores.workouts.workout(id: running.id)?.id == nil, "nothing reached history")
        await task.value
        #expect(store.exit == .route(.discarded), "the stream's own word of the discard changes nothing")
    }

    @Test("S5. The dialog's dismissal and its Discard button may arrive in either order")
    func discard_afterTheDialogWentAway_isStillADiscard() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        store.send(.finish)
        store.send(.keepLifting)
        store.send(.discard)
        #expect(store.discardAttempt == 1)
        await store.discard()
        #expect(store.exit == .route(.discarded))
        await task.value
    }

    @Test("S6. A discard the session refuses is shown, and the workout stays live and on screen")
    func discard_refused_isShownAndTheWorkoutStays() async throws {
        let running = try Fixtures.seedSession()
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        await scene.probe.fail(.append)
        store.send(.finish)
        store.send(.discard)
        await store.discard()

        #expect(store.dialog == .discardFailed)
        #expect(!store.isDiscarding)
        #expect(store.exit == nil)
        #expect(store.shown?.id == running.id)
        #expect(store.model.header?.isEnabled == true)
        #expect(try await scene.holds(running))
        let alert = WorkoutPresentation.discardFailedAlert
        #expect(alert.title == "Couldn't discard this workout")
        #expect(alert.message == "It's still in progress. Try again.")

        // "OK", then the same again, now that the store answers.
        store.send(.keepLifting)
        #expect(store.dialog == .discardFailed)
        store.send(.dismissFailure)
        #expect(store.dialog == nil)
        store.send(.finish)
        store.send(.discard)
        #expect(store.discardAttempt == 2)
        await store.discard()
        #expect(store.exit == .route(.discarded))
        #expect(try await scene.session.current()?.id == nil)
        await task.value
    }

    @Test("S7. A discard that finds the workout already ended is no failure: the session's word closes the cover")
    func discard_alreadyEnded_isNoFailure() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        // The cover's task is not listening for the moment, so the end below is not heard before the call.
        task.cancel()
        await task.value
        store.send(.discard)
        try await scene.fake?.discard(endedAt: Fixtures.now)

        await store.discard()
        #expect(store.dialog == nil)
        #expect(!store.isDiscarding)
        #expect(store.exit == nil)
        await store.follow()
        #expect(store.exit == .nothingToShow)
    }

    @Test("S13. A discard still running when the cover goes away is completed by the host, and is no failure")
    func discard_coverGoesAwayWhileItRuns_isCompleted() async throws {
        let scene = try await Scene.onHost(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        await scene.probe.hold(.append)
        store.send(.discard)
        let work = Task { await store.discard() }
        try await scene.probe.waitUntilHeld()
        work.cancel()
        task.cancel()
        await scene.probe.release()
        await work.value

        #expect(store.dialog == nil)
        #expect(store.exit == .route(.discarded))
        #expect(try await scene.session.current()?.id == nil)
    }

    @Test("S13. A discard cancelled with the cover before the session answered shows and fails nothing")
    func discard_cancelledBeforeItsAnswer_showsNothing() async throws {
        let gate = Gate()
        let running = try Fixtures.seedSession()
        let scene = try Scene.on(GatedSession(base: FakeWorkoutSessionClient(live: running), gate: gate))
        let (store, task) = await scene.following()
        store.send(.discard)
        let work = Task { await store.discard() }
        await gate.waitForArrival()
        work.cancel()
        await gate.open()
        await work.value
        #expect(store.dialog == nil)
        #expect(!store.isDiscarding)
        #expect(store.exit == nil)
        #expect(try await scene.holds(running))
        task.cancel()
    }

    @Test("A discard with none asked for does nothing")
    func discard_notAsked_doesNothing() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        await store.discard()
        #expect(store.exit == nil)
        #expect(await scene.asked() == [])
        task.cancel()
    }
}
