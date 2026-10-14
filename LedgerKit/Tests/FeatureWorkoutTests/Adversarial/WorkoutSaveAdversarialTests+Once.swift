import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S7a criteria 8, 10, 13, 14, 17 and 18: a workout ends once. Two taps on "Save workout", "Save"
/// and "Discard" in either order, "Keep lifting" while it saves, the cover's tasks starting again and the
/// session's updates ending while the session holds the call.
extension WorkoutSaveAdversarialTests {
    /// A cover with the first set logged and shown, "Finish" tapped, and every end held by the session.
    static func askingToEnd() async -> SaveCover {
        let cover = await SaveCover()
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        await cover.session.holdEveryEnd()
        cover.clock.withValue { $0 += 600 }
        cover.send(.finish)
        return cover
    }

    nonisolated static let savedAt = Fixtures.now.addingTimeInterval(600)

    @Test("Two taps on Save workout, and every other control while it saves: one finish, at the first tap")
    func save_tappedTwice_andEverythingElse_savesOnce() async {
        let cover = await Self.askingToEnd()
        cover.send(.save)
        cover.clock.withValue { $0 += 5 }
        cover.send(.save, .discard, .keepLifting, .retrySave, .dismissFailure, .minimize, .finish)
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 1)), .unlog(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the session to be asked") { cover.session.endsWaiting.value == 1 }
        await cover.rest()
        #expect(cover.store.saveAttempt == 1)
        #expect(cover.store.discardAttempt == 0)
        #expect(cover.store.dialog == .finish, "the sheet stays up while it saves")
        #expect(cover.store.finishSheet?.isEnabled == false)
        #expect(cover.store.finishSheet?.canSave == false)
        #expect(cover.store.queue.isEmpty, "a tap made while it saves is not kept for later")
        #expect(cover.store.exit == nil)
        #expect(await cover.session.finishesAsked == [Self.savedAt])
        #expect(await cover.session.discardsAsked == 0)

        await cover.session.releaseEnd()
        await cover.until("the cover to close") { cover.store.exit != nil }
        await cover.settle()
        #expect(cover.exits == [.route(.saved(cover.running.id))])
        #expect(await cover.session.reached.suffix(1) == [.finished(Self.savedAt)])
        #expect(await cover.session.ended?.doneSets == 1)
        #expect(await cover.fault() == nil)
        #expect(await cover.haptics.played.count { $0 == .workoutFinished } == 1)
        await cover.close()
    }

    @Test("Discard, then Save workout while the discard runs: no finish is asked, and the workout is discarded")
    func discard_thenSave_discardsOnce() async {
        let cover = await Self.askingToEnd()
        cover.send(.discard, .save, .finish, .save)
        await cover.until("the session to be asked") { cover.session.endsWaiting.value == 1 }
        await cover.rest()
        #expect(!cover.store.isSaving)
        #expect(cover.store.saveAttempt == 0)
        #expect(await cover.session.finishesAsked == [])
        await cover.session.releaseEnd()
        await cover.until("the cover to close") { cover.store.exit != nil }
        await cover.settle()
        #expect(cover.exits == [.route(.discarded)])
        #expect(await cover.session.finishesAsked == [])
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("The cover's tasks start again while the session holds the finish: asked again for the same end, saved once")
    func tasksRestart_midFinish_savesOnce() async {
        let cover = await Self.askingToEnd()
        cover.send(.save)
        await cover.until("the session to be asked") { cover.session.endsWaiting.value == 1 }
        cover.clock.withValue { $0 += 45 }
        await cover.restartTasks(awaitingTheOld: false)
        await cover.until("the session to be asked again") { cover.session.endsWaiting.value == 2 }
        #expect(cover.store.isSaving)
        #expect(cover.store.dialog == .finish)
        cover.send(.discard, .save, .keepLifting)
        #expect(await cover.session.finishesAsked == [Self.savedAt, Self.savedAt], "the end is the first tap's")
        await cover.session.releaseEnd()
        await cover.session.releaseEnd()
        await cover.until("the cover to close") { cover.store.exit != nil }
        await cover.settle()
        #expect(cover.exits == [.route(.saved(cover.running.id))])
        #expect(cover.store.dialog == nil, "no failure is shown for the call that found the workout ended")
        #expect(await cover.session.reached.count { $0 == .finished(Self.savedAt) } == 1)
        #expect(await cover.session.discardsAsked == 0)
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("The same with the second call answered first, and with the new stream's first update kept back")
    func tasksRestart_midFinish_answersInTheOtherOrder() async {
        let cover = await Self.askingToEnd()
        cover.send(.save)
        await cover.until("the session to be asked") { cover.session.endsWaiting.value == 1 }
        await cover.session.keepStreamsBehind(first: true)
        await cover.restartTasks(awaitingTheOld: false)
        await cover.until("the session to be asked again") { cover.session.endsWaiting.value == 2 }
        #expect(!cover.store.isHearingTheSession)
        // The first call, whose caller is gone, is the one that saves: its answer reaches nobody. The
        // second then finds no workout, and the stream says only that none is live.
        await cover.session.releaseEnd()
        await cover.rest()
        await cover.session.releaseEnd()
        await cover.rest()
        #expect(cover.store.exit == nil || cover.store.exit == .route(.saved(cover.running.id)))
        await cover.session.keepStreamsBehind(false)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(cover.exits == [.route(.saved(cover.running.id))], "criterion 18: never nothingToShow, never a failure")
        #expect(cover.store.dialog == nil)
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("The session's updates end while it holds the finish: the failed screen, then closed as saved")
    func updatesEnd_midFinish_closesAsSaved() async {
        let cover = await Self.askingToEnd()
        cover.send(.save)
        await cover.until("the session to be asked") { cover.session.endsWaiting.value == 1 }
        await cover.session.endStreams()
        await cover.until("the failed screen") { cover.store.shown == nil }
        #expect(!cover.store.isSaving)
        #expect(cover.store.dialog == nil, "the sheet has no workout to ask about")
        #expect(cover.store.exit == nil)
        cover.send(.save, .retrySave, .discard, .finish)
        #expect(cover.store.saveAttempt == 1)
        #expect(cover.store.discardAttempt == 0)
        await cover.session.releaseEnd()
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(cover.exits == [.route(.saved(cover.running.id))])
        #expect(await cover.session.finishesAsked.count == 1)
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("The updates end while the save waits for a held tap: withdrawn, nothing asked, the failed screen closes")
    func updatesEnd_whileTheSaveWaitsForATap() async {
        let cover = await Self.askingToEnd()
        await cover.session.holdEveryApply()
        cover.send(.keepLifting)
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 1)), .log(exerciseIndex: 0, setID: cover.set(0, 2)))
        await cover.until("the first tap to reach the session") { cover.session.waiting.value == 1 }
        cover.send(.finish, .save)
        #expect(cover.store.isSaving)
        await cover.session.endStreams()
        await cover.until("the failed screen") { cover.store.shown == nil }
        await cover.session.release()
        await cover.rest()
        #expect(!cover.store.isSaving)
        #expect(await cover.session.finishesAsked == [], "a workout is not saved without the taps the lifter made")
        #expect(cover.store.queue.isEmpty)
        #expect(cover.store.exit == nil)
        cover.send(.minimize)
        #expect(cover.store.exit == .route(.minimized), "the failed screen's Close")
        #expect(await cover.session.current()?.doneSets == 2, "the tap that was with the session landed")
        await cover.close()
    }

    @Test("The cover goes away for good while the session holds the finish: saved, and nothing is shown")
    func coverGone_midFinish() async {
        let cover = await Self.askingToEnd()
        cover.send(.save)
        await cover.until("the session to be asked") { cover.session.endsWaiting.value == 1 }
        await cover.close()
        #expect(await cover.session.ended?.phase == .finished, "the host completes the call")
        #expect(cover.store.dialog != .saveFailed, "a cancellation is not a failed save")
        #expect(await cover.session.finishesAsked.count == 1)
    }
}
