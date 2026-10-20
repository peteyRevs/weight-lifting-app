import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7b criteria 25, 26, 30, 31, 36 and 37 under attack: when the receipt shows and when the cover
/// closes as saved without one, "Done" closing it once, the records line, and the live record. Against the
/// fake session, the real host over the probed in-memory stores, and the doubles below.
@MainActor
@Suite("Workout receipt (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutReceiptAdversarialTests {
    typealias Failure = WorkoutStoreSaveFailureTests
    typealias Pump = WorkoutStorePumpTests
    typealias Receipt = WorkoutStoreReceiptTests
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    // MARK: Criterion 25: which save shows a receipt

    /// F10-S7b-1. A save the host refused (its end waits in the log), "Close", and a new "Save workout" a
    /// few minutes later in the same cover. `send(.save)` was accepted, so criterion 25 says the receipt
    /// shows, from `finish`'s answer or the ending update, whichever comes first. The host completes the
    /// waiting end, at the first tap's time, and publishes it before it answers.
    @Test("After a refused save and Close, a new Save workout in the same cover shows the receipt")
    func closeThenSaveAgain_showsTheReceipt() async throws {
        let running = try Save.logged(1)
        let date = LockIsolated(Fixtures.now.addingTimeInterval(900))
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Failure.saving(scene, at: date)
        await scene.probe.fail(.materialize)
        await store.save()
        #expect(store.dialog == .saveFailed)
        store.send(.dismissFailure)

        date.withValue { $0 += 240 }
        store.send(.finish)
        store.send(.save)
        #expect(store.isSaving, "the second Save workout is accepted")
        await store.save()
        await eventually { store.saved != nil || store.exit != nil }

        #expect(try await scene.stores.workouts.workout(id: running.id) != nil, "the workout is in history")
        #expect(store.saved?.id == running.id, "the lifter saved it in this cover: its receipt shows")
        #expect(store.exit == nil, "the cover stays up until Done")
        task.cancel()
        await task.value
    }

    /// The same, with the ending update and the answer in both orders: the receipt must not depend on which
    /// reaches the store first. The session publishes its stored end (the first tap's) and answers with it.
    @Test(
        "A save whose session ends the workout at the end it already held shows the receipt in either order",
        arguments: [true, false]
    )
    func heldEnd_eitherOrder_showsTheReceipt(answerFirst: Bool) async throws {
        let running = try Save.logged(1)
        let first = Fixtures.now.addingTimeInterval(900)
        let session = KeptEndSession(live: running, keptEnd: first, answerFirst: answerFirst)
        let scene = try Scene.on(session)
        let store = scene.store { $0.date = .constant(first.addingTimeInterval(240)) }
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        store.send(.finish)
        store.send(.save)
        let saving = Task { await store.save() }
        await session.waitUntilEnded()
        await giveWay()
        await session.answer()
        await saving.value
        await eventually { store.saved != nil || store.exit != nil }
        #expect(store.saved?.id == running.id, answerFirst ? "answer first" : "ending update first")
        #expect(store.exit == nil)
        task.cancel()
        await task.value
    }

    /// Criterion 17 under a call already sent: the save's `finish` has reached the session and waits there
    /// when another hand ends the workout at another end. The stream's ending update is not this cover's
    /// save, so the cover closes as saved with no receipt. (Nothing else pins the end comparison of
    /// `isSavedHere`: without it every other test passes.)
    @Test("Another hand's end while this cover's finish is in flight closes as saved, with no receipt")
    func endedElsewhere_whileTheCallIsInFlight_noReceipt() async throws {
        let running = try Save.logged(1)
        let gate = Gate()
        let fake = FakeWorkoutSessionClient(live: running)
        let scene = try Scene.on(HeldFinishSession(base: fake, gate: gate))
        let (store, task) = await Receipt.following(scene)
        store.send(.finish)
        store.send(.save)
        let saving = Task { await store.save() }
        await gate.waitForArrival()
        #expect(store.pendingSave?.wasSent == true)
        _ = try await fake.finish(endedAt: Fixtures.now.addingTimeInterval(-5))
        await task.value
        await gate.open()
        await saving.value
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.saved == nil, "the end is another hand's")
    }

    @Test("After a refused save and Close, a tap that completes the waiting end closes as saved, with no receipt (R10)")
    func close_thenATap_noReceipt() async throws {
        let running = try Save.logged(1)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Failure.saving(scene)
        await scene.probe.fail(.materialize)
        await store.save()
        store.send(.dismissFailure)
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1])))
        await store.drain()
        await eventually { store.exit != nil || store.saved != nil }
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.saved == nil)
        #expect(store.receipt == nil)
        await task.value
    }

    @Test("The ending update first, the answer held: the receipt shows at once, once; the answer changes nothing")
    func endingUpdateFirst_answerHeld() async throws {
        let running = try Save.logged(2)
        let haptics = FakeHaptics()
        let session = KeptEndSession(live: running, keptEnd: nil, answerFirst: false)
        let scene = try Scene.on(session)
        let store = scene.store { $0.haptics = haptics }
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        store.send(.finish)
        store.send(.save)
        let saving = Task { await store.save() }
        await session.waitUntilEnded()
        await eventually { store.saved != nil || store.exit != nil }
        #expect(store.saved?.id == running.id, "the stream's word is enough")
        #expect(store.exit == nil)
        #expect(!store.isSaving)
        let shown = store.receipt
        await session.answer()
        await saving.value
        await task.value
        #expect(store.receipt == shown, "the answer sets nothing again")
        #expect(store.exit == nil)
        #expect(await haptics.played == [.workoutFinished])

        store.send(.done)
        store.send(.done)
        #expect(store.exit == .route(.saved(running.id)))
        // A cover's tasks starting again after Done: the new stream's first update says nothing is live.
        await store.follow()
        #expect(store.exit == .route(.saved(running.id)), "set once")
    }

    @Test("Done before any receipt, and on a closing cover, does nothing")
    func done_withoutAReceipt_doesNothing() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Receipt.following(scene)
        store.send(.done)
        #expect(store.exit == nil)
        store.send(.finish)
        store.send(.done)
        #expect(store.dialog == .finish, "Done is not Keep lifting")
        #expect(store.exit == nil)
        task.cancel()
        await task.value
    }

    @Test("Discard never shows a receipt; it closes as discarded")
    func discard_showsNoReceipt() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Receipt.following(scene)
        store.send(.finish)
        store.send(.discard)
        await store.discard()
        await task.value
        #expect(store.exit == .route(.discarded))
        #expect(store.saved == nil)
    }
}
