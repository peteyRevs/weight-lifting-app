import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7a round 2: the fix round's rulings attacked. "Discard" after a save was asked for, in the same
/// cover and in a cover opened again after "Minimize" (the stated limit); the save's wait when the session is
/// not heard (no spin); and a cover whose tasks start again under a failed save.
extension WorkoutSaveAdversarialTests {
    /// A failed save on the real host (the store refuses to keep the workout, so its end waits in the log),
    /// then "Close" and "Minimize". Returns the scene, with the first cover gone.
    static func failedThenMinimized(_ running: WorkoutState, at date: LockIsolated<Date>) async -> WorkoutScene? {
        guard let scene = try? await Scene.onHost(live: running) else {
            return nil
        }
        let (store, following) = await WorkoutStoreSaveFailureTests.saving(scene, at: date)
        defer { following.cancel() }
        await scene.probe.fail(.materialize)
        await store.save()
        #expect(store.dialog == .saveFailed)
        store.send(.dismissFailure)
        store.send(.minimize)
        #expect(store.exit == .route(.minimized))
        return scene
    }

    @Test("S7a-8: a cover opened again after a failed save offers Discard, and a tap on it saves the workout")
    func reopened_afterAFailedSave_discardSaves() async throws {
        let running = try WorkoutStoreSaveTests.logged(2)
        let tapped = Fixtures.now.addingTimeInterval(600)
        let date = LockIsolated(tapped)
        let scene = try #require(await Self.failedThenMinimized(running, at: date))
        // The disk has room again; the lifter opens the workout from Today and asks to discard it.
        await scene.probe.heal()
        date.withValue { $0 += 300 }
        let store = scene.store(WorkoutStoreSaveTests.moving(date))
        let following = Task { await store.follow() }
        defer { following.cancel() }
        guard await eventually("the cover to show the workout", { store.shown != nil }) else {
            return
        }
        store.send(.finish)
        #expect(store.finishSheet?.discard == "Discard", "the new cover does not know an end waits (R10)")
        store.send(.discard)
        let work = Task { await store.discard() }
        await SaveCover.ended([work], "the discard")
        guard await eventually("the cover to close", { store.exit != nil }) else {
            return
        }
        let stored = try await scene.stores.workouts.workout(id: running.id)
        // As built: the host completes the waiting end before the discard, which then finds no workout.
        #expect(store.exit == .route(.saved(running.id)))
        #expect(stored?.endedAt == tapped, "saved at the first tap on Save workout")
        withKnownIssue("S7a-8: a tap on Discard ends as saved, and Today shows a Logged card") {
            #expect(store.exit == .route(.discarded))
            #expect(stored == nil)
        }
    }

    @Test("In the same cover, a failed save leaves no Discard: also after its tasks start again, and in a walk")
    func sameCover_afterAFailedSave_noDiscard_acrossARestart() async {
        let cover = await Self.askingToEnd()
        await cover.session.holdEveryEnd(false)
        await cover.session.failFinish(with: [SaveSession.Refused(), SaveSession.Refused()])
        cover.send(.save)
        guard await cover.until("the failure to be shown", { cover.store.dialog == .saveFailed }) else {
            return
        }
        await cover.restartTasks(awaitingTheOld: false)
        await cover.rest()
        #expect(cover.store.dialog == .saveFailed, "the alert outlives the tasks starting again")
        cover.send(.retrySave)
        guard await cover.until("the second failure", { cover.store.dialog == .saveFailed }) else {
            return
        }
        #expect(cover.store.saveAttempt == 2, "a new attempt: a new alert")
        cover.send(.dismissFailure, .finish)
        #expect(cover.store.finishSheet?.discard == nil)
        cover.send(.discard)
        await cover.rest()
        #expect(cover.store.discardAttempt == 0)
        #expect(await cover.session.discardsAsked == 0)
        cover.send(.save)
        guard await cover.until("the cover to close", { cover.store.exit != nil }) else {
            return
        }
        #expect(cover.exits == [.route(.saved(cover.running.id))])
        #expect(await cover.session.finishesAsked == Array(repeating: Self.savedAt, count: 2) + [cover.clock.value])
        await cover.close()
    }

    @Test("A save waiting for taps while the session is not heard does not spin: a bounded number of drains")
    func waitingSave_notHeard_drainsBounded() async {
        let cover = await SaveCover()
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        await cover.session.holdEveryApply()
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 1)), .log(exerciseIndex: 0, setID: cover.set(0, 2)))
        await cover.until("a tap to reach the session") { cover.session.waiting.value == 1 }
        cover.send(.finish, .save)
        await cover.session.keepStreamsBehind(first: true)
        await cover.restartTasks(awaitingTheOld: false)
        await cover.session.release()
        let before = cover.store.drainPasses
        for _ in 0 ..< 5000 {
            await Task.yield()
        }
        let passes = cover.store.drainPasses - before
        #expect(passes <= 8, "\(passes) drains in 5,000 turns while nothing can be applied")
        #expect(cover.store.isSaving)
        #expect(await cover.session.finishesAsked == [])
        await cover.session.keepStreamsBehind(false)
        await cover.session.holdEveryApply(false)
        await cover.session.release()
        guard await cover.until("the cover to close", { cover.store.exit != nil }) else {
            return
        }
        #expect(await cover.session.ended?.doneSets == 3, "the taps that waited are in the saved workout")
        await cover.close()
    }
}
