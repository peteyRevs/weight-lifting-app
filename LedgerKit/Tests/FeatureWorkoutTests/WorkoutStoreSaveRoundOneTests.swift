import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, fix round 1: the save's wait does not spin while the session is not heard (G3-1); "Discard" is
/// not offered once a save was asked for, and a tap on it never ends as saved (S7a-3); the system's own
/// dismissal of a dialog takes that dialog down and no other (G3 notes).
@MainActor
@Suite("WorkoutStore save, fix round 1", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSaveRoundOneTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    @Test("A save waiting for a tap while the session is not heard does not spin: a bounded number of drains")
    func waitingSave_whileNotHeard_doesNotSpin() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        // The cover's tasks restart: the follow is gone, a tap and a save wait, and a pump runs.
        task.cancel()
        await task.value
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1])))
        store.send(.save)
        let pump = Task { await store.pump() }
        let saving = Task { await store.save() }
        await giveWay()
        let passes = store.drainPasses
        #expect(passes <= 4, "\(passes) drains while nothing could be applied")
        await giveWay()
        #expect(store.drainPasses == passes, "and none more while nothing changes")
        #expect(await scene.asked() == [])

        // The follow starts again: the tap is applied, then the save.
        let again = Task { await store.follow() }
        await saving.value
        #expect(await scene.asked() == [.changed, .finished(Fixtures.now)])
        #expect(store.exit == .route(.saved(running.id)))
        pump.cancel()
        await again.value
    }

    @Test("After a failed save and Close the sheet offers no Discard, and a sent Discard does nothing")
    func afterAFailedSave_noDiscard() async throws {
        let running = try Save.logged(2)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await WorkoutStoreSaveFailureTests.saving(scene)
        #expect(store.finishSheet?.discard == "Discard", "offered until the session is asked")
        await scene.probe.fail(.materialize)
        await store.save()
        store.send(.dismissFailure)
        store.send(.finish)
        #expect(store.finishSheet?.discard == nil)
        #expect(store.finishSheet?.canSave == true)
        store.send(.discard)
        #expect(!store.isDiscarding)
        #expect(store.discardAttempt == 0)
        await store.discard()
        #expect(store.exit == nil)
        #expect(store.dialog == .finish)
        // "Save workout" still saves it.
        store.send(.save)
        await store.save()
        #expect(store.exit == .route(.saved(running.id)))
        await task.value
    }

    @Test("Discard is offered when a save never reached the session (the queue left no set)")
    func saveNeverSent_keepsDiscard() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.unlog(exerciseIndex: 0, setID: Pump.sets(0, of: running)[0])))
        store.send(.finish)
        store.send(.save)
        await store.save()
        #expect(!store.isSaving)
        #expect(store.finishSheet?.discard == "Discard")
        store.send(.discard)
        await store.discard()
        #expect(store.exit == .route(.discarded))
        await task.value
    }

    @Test("The system's dismissal of one dialog takes down that dialog alone")
    func dismissed_takesDownItsOwnDialogOnly() async throws {
        let running = try Save.logged(1)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await WorkoutStoreSaveFailureTests.saving(scene)
        await scene.probe.fail(.materialize)
        await store.save()
        #expect(store.dialog == .saveFailed)
        // A late word that the discard's or the change's alert went changes nothing here.
        store.send(.dismissed(.discardFailed))
        store.send(.dismissed(.editFailed))
        store.send(.keepLifting)
        #expect(store.dialog == .saveFailed)
        store.send(.dismissed(.saveFailed))
        #expect(store.dialog == nil)
        task.cancel()
    }
}
