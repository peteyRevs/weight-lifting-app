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
        await SaveCover.ended([work], "the discard")
        #expect(store.exit == .route(.discarded))
        #expect(try await scene.session.current() == nil)
        #expect(try await scene.stores.workouts.workout(id: running.id) == nil)
    }

    /// The same over this suite's `SaveSession`, which answers a cancelled discard as the host above does. It
    /// once threw `CancellationError` instead: the store let the discard go, the cover stayed up on the
    /// dropped workout until an update came, and a save tapped meanwhile closed it as saved (the save
    /// walk's nightly seed 5115691).
    @Test("This suite's session, too: a discard whose task is cancelled ends as a discard, with no update heard")
    func session_cancelledDiscard_endsAsADiscard() async {
        let cover = await Self.withASetLogged()
        await cover.session.holdEveryEnd()
        await cover.session.keepStreamsBehind()
        cover.send(.finish, .discard)
        await cover.until("the discard to be held") { cover.session.endsWaiting.value == 1 }
        await cover.restartTasks(awaitingTheOld: false)
        #expect(cover.store.isDiscarding, "the cancelled call has not ended")
        cover.send(.finish, .save)
        #expect(!cover.store.isSaving, "so no save can be tapped over the discard")
        await cover.session.releaseEnd()
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(cover.store.exit == .route(.discarded))
        #expect(await cover.session.ended?.phase == .discarded)
        await cover.close()
    }

    /// A cover with a set logged, so that "Save workout" would save.
    static func withASetLogged() async -> SaveCover {
        let cover = await SaveCover()
        cover.tap(.log(exerciseIndex: 1, setID: cover.set(1, 0)))
        await cover.until("the set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        return cover
    }

    /// A cover whose discard was cancelled, by a client that throws its cancelled caller `CancellationError`
    /// once the workout is dropped (`SaveSession.throwToACancelledDiscard`), with the ending update kept back.
    static func discardThrownAtItsCancelledCaller() async -> SaveCover {
        let cover = await withASetLogged()
        await cover.session.holdEveryEnd()
        await cover.session.throwToACancelledDiscard()
        await cover.session.keepStreamsBehind()
        cover.send(.finish, .discard)
        await cover.until("the discard to be held") { cover.session.endsWaiting.value == 1 }
        await cover.restartTasks(awaitingTheOld: false)
        // The new follow hears the live workout first; a stream opened after the discard would open on none.
        await cover.rest()
        await cover.until("the new follow to hear the session") { cover.store.isHearingTheSession }
        await cover.session.releaseEnd()
        await eventually("the workout to be dropped") { await cover.session.ended?.phase == .discarded }
        await cover.rest()
        return cover
    }

    @Test("A client that throws a cancelled discard: the store goes on discarding, and the update closes it so")
    func throwingClient_cancelledDiscard_closesAsDiscarded() async {
        let cover = await Self.discardThrownAtItsCancelledCaller()
        #expect(cover.store.exit == nil, "the update that says how it ended is kept back")
        #expect(cover.store.isDiscarding, "the discard went through: the store goes on discarding")
        cover.send(.finish, .save)
        #expect(!cover.store.isSaving, "so no save can be tapped over a workout already dropped")
        await cover.session.keepStreamsBehind(false)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(cover.store.exit == .route(.discarded))
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("A client that throws a cancelled discard, then the updates end: the failed screen's Close closes")
    func throwingClient_cancelledDiscard_updatesEnd_closeCloses() async {
        let cover = await Self.discardThrownAtItsCancelledCaller()
        await cover.session.endStreams()
        await cover.until("the failed screen") {
            if case .failed = cover.store.workout {
                return true
            }
            return false
        }
        #expect(!cover.store.isDiscarding, "no call runs for the discard any more")
        cover.send(.minimize)
        #expect(cover.store.exit != nil, "the failed screen's Close closes the cover")
        await cover.close()
    }
}
