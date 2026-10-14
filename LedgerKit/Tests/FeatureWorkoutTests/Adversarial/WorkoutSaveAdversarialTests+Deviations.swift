import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7a, deviation 2 of the notes: a cover closes as saved on a stream that opens on no workout only
/// when it had asked the session to finish. What that leaves, with a second hand and on one phone.
extension WorkoutSaveAdversarialTests {
    @Test("Deviation 2: with a save tapped and not yet sent, a stream that opens on no workout has nothing to show")
    func noWorkout_beforeTheSaveWasSent_isNothingToShow() async throws {
        let (cover, _) = await Self.withThreeTapsWaiting()
        cover.send(.finish, .save)
        // Another hand saves the workout; the cover's tasks start again and hear only that none is live.
        await cover.session.keepStreamsBehind(first: true)
        _ = try await cover.session.elsewhere(.finished(endedAt: cover.clock.value))
        await cover.restartTasks(awaitingTheOld: false)
        await cover.session.holdEveryApply(false)
        await cover.session.release()
        await cover.session.keepStreamsBehind(false)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(cover.store.exit == .nothingToShow, "as before the slice: it did not ask, so it does not say saved")
        #expect(await cover.session.finishesAsked == [], "this cover asked for no finish")
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    /// The notes' input for F17, seen: the cover closes as saved on a workout that was discarded. It takes a
    /// second hand, and a stream that says only "none is live" in place of how the workout ended.
    @Test("Discarded by another hand, unheard, under a save that was sent: the cover closes as saved (as built)")
    func discardedElsewhere_unheard_closesAsSaved_asBuilt() async throws {
        let cover = await Self.askingToEnd()
        await cover.session.holdEveryEnd(false)
        await cover.session.keepStreamsBehind()
        _ = try await cover.session.elsewhere(.discarded(endedAt: cover.clock.value))
        cover.send(.save)
        await cover.until("the session to be asked") { cover.session.finishCalls.value == 1 }
        await cover.rest()
        #expect(cover.store.isSaving, "no live workout is no failure: the ending update says how")
        await cover.session.keepStreamsBehind(first: true)
        await cover.restartTasks(awaitingTheOld: false)
        await cover.rest()
        await cover.session.keepStreamsBehind(false)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(await cover.session.ended?.phase == .discarded)
        #expect(cover.store.exit == .route(.saved(cover.running.id)), "as built: Today will show no Logged card")
        await cover.close()
    }

    @Test("On the real host one phone cannot do that: a discard whose task is cancelled still ends as a discard")
    func host_cancelledDiscard_staysADiscard() async throws {
        let running = try WorkoutStoreSaveTests.logged(1)
        let scene = try await Scene.onHost(live: running)
        let (store, following) = await scene.following()
        await scene.probe.hold(.append)
        store.send(.finish)
        store.send(.discard)
        let work = Task { await store.discard() }
        try await scene.probe.waitUntilHeld()
        work.cancel()
        following.cancel()
        await giveWay()
        #expect(store.isDiscarding, "the host does not let a cancelled caller go before the call has ended")
        store.send(.finish)
        store.send(.save)
        #expect(!store.isSaving, "so no save can be tapped over a discard that is still running")
        await scene.probe.release()
        await work.value
        #expect(store.exit == .route(.discarded))
        #expect(try await scene.session.current() == nil)
        #expect(try await scene.stores.workouts.workout(id: running.id) == nil)
    }
}
