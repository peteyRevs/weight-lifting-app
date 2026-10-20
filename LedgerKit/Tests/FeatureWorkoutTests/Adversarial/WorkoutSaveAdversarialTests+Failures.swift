import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// G2, F10 S7a criteria 11, 12, 15 and 16, and deviation 2 of the notes: a save that fails, again and again;
/// "Close" and what it leaves, on the real host and at the next launch; a change refused under the sheet
/// and under a waiting save; an end the engine will not take; and a workout another hand discarded, unheard.
extension WorkoutSaveAdversarialTests {
    typealias Scene = WorkoutScene

    @Test(
        "Try again failing N times in a row: the alert each time, the workout untouched, the first tap's end",
        arguments: [1, 2, 3, 8]
    )
    func tryAgain_failingInARow(failures: Int) async {
        let cover = await Self.askingToEnd()
        await cover.session.holdEveryEnd(false)
        let kinds: [any Error] = [
            SaveSession.Refused(), WorkoutSessionError.incompleteLog(cover.running.id), CancellationError(),
            WorkoutSessionError.invalidEndDate
        ]
        await cover.session.failFinish(with: (0 ..< failures).map { kinds[$0 % kinds.count] })
        let before = await cover.session.current()
        cover.send(.save)
        for attempt in 1 ... failures {
            guard await cover.until("failure \(attempt) to be shown", { cover.store.dialog == .saveFailed }) else {
                break
            }
            #expect(!cover.store.isSaving)
            #expect(cover.store.exit == nil)
            #expect(cover.store.saveAttempt == attempt, "each failure is on its own attempt: the two alerts take turns")
            #expect(cover.store.model.header?.isEnabled == true)
            #expect(await unchanged(cover.session.current(), before), "failure \(attempt) changed the workout")
            #expect(cover.store.shown == before)
            cover.clock.withValue { $0 += 30 }
            cover.send(.retrySave)
            #expect(cover.store.dialog == nil)
            // The alert's own dismissal arriving after its button, as S4's alerts send it.
            cover.send(.dismissFailure)
            #expect(cover.store.isSaving || cover.store.exit != nil)
        }
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(cover.exits == [.route(.saved(cover.running.id))])
        #expect(await cover.session.finishesAsked == Array(repeating: Self.savedAt, count: failures + 1))
        #expect(await cover.session.ended?.doneSets == 1)
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("The failed save's alert offers Try again and Close, and no Discard")
    func failedSave_offersNoDiscard() {
        let alert = WorkoutPresentation.saveFailedAlert
        #expect(alert == WorkoutSaveFailedModel(
            title: "Couldn't save this workout",
            message: "It's still on this iPhone. Try again.",
            retry: "Try again",
            close: "Close"
        ))
        let words = [alert.title, alert.message, alert.retry, alert.close].joined(separator: " ").lowercased()
        #expect(!words.contains("discard"))
        #expect(!words.contains("ledger"), "no product name, no promise (R7)")
    }

    @Test("Close after a failed save, on the host: live, not in history, Minimize answers; the next launch saves it")
    func close_afterAFailure_isSavedAtTheNextLaunch() async throws {
        let running = try WorkoutStoreSaveTests.logged(3)
        let tapped = Fixtures.now.addingTimeInterval(1200)
        let scene = try await Scene.onHost(live: running)
        let (store, following) = await WorkoutStoreSaveFailureTests.saving(scene, at: LockIsolated(tapped))
        await scene.probe.fail(.materialize)
        await store.save()
        #expect(store.dialog == .saveFailed)
        store.send(.dismissFailure)
        #expect(store.dialog == nil)
        #expect(store.exit == nil)
        #expect(!store.isSaving)
        #expect(store.shown?.doneSets == 3, "the cover shows the workout as it was")
        #expect(try await scene.session.current()?.phase == .live)
        #expect(try await scene.stores.workouts.workout(id: running.id) == nil)
        store.send(.minimize)
        #expect(store.exit == .route(.minimized), "the lifter is not held on a workout that would not save")
        following.cancel()

        // The app is launched again: a new host over the same stores.
        let relaunched = LocalWorkoutSessionActor(
            events: scene.stores.events,
            workouts: scene.stores.workouts,
            programs: scene.stores.programs,
            device: Fixtures.deviceID,
            now: { Fixtures.now.addingTimeInterval(86400) }
        )
        #expect(try await relaunched.current() == nil, "the unsaved workout is not shown again")
        let stored = try #require(try await scene.stores.workouts.workout(id: running.id), "the launch saved it")
        #expect(stored.endedAt == tapped, "ended when Save workout was tapped, not at the launch")
        #expect(stored.doneSets == 3)
    }

    /// F10 S7a fix round 1 (the orchestrator's ruling (a) on ruling 5; edited by the implementer, for the
    /// tester's audit): this test pinned "After Close, the sheet's Discard saves the workout: as built". The
    /// host cannot withdraw a waiting end, so "Discard" is no longer offered once a save was asked for.
    @Test("After a failed save and Close: no Discard, a sent one changes nothing, Save saves at the first end")
    func close_thenNoDiscard_saveSavesAtTheFirstEnd() async throws {
        let running = try WorkoutStoreSaveTests.logged(2)
        let scene = try await Scene.onHost(live: running)
        let date = LockIsolated(Fixtures.now)
        let (store, following) = await WorkoutStoreSaveFailureTests.saving(scene, at: date)
        defer { following.cancel() }
        await scene.probe.fail(.materialize)
        await store.save()
        store.send(.dismissFailure)
        store.send(.finish)
        #expect(store.finishSheet?.discard == nil, "the sheet offers no Discard once a save was asked for")
        store.send(.discard)
        await store.discard()
        await giveWay()
        #expect(store.exit == nil, "a sent Discard ends nothing")
        #expect(store.dialog == .finish, "and leaves the sheet as it was")
        #expect(!store.isDiscarding)
        #expect(try await scene.session.current()?.phase == .live)
        // G2 round 2: the clock moves before the second tap, so "the first tap's end" is told from its own.
        date.withValue { $0 += 240 }
        store.send(.save)
        await store.save()
        // G2 S7b (F10-S7b-1): this save was asked for in this cover, so its receipt shows (criterion 25),
        // whichever of the answer and the ending update comes first; "Done" then closes the cover.
        guard await eventually("the receipt or the cover's exit", { store.saved != nil || store.exit != nil }) else {
            return
        }
        #expect(store.saved?.id == running.id, "the receipt of the save made in this cover")
        #expect(store.exit == nil, "the cover stays up on the receipt")
        store.send(.done)
        #expect(store.exit == .route(.saved(running.id)))
        let stored = try #require(try await scene.stores.workouts.workout(id: running.id))
        #expect(stored.doneSets == 2)
        #expect(stored.endedAt == Fixtures.now, "the end of the first tap on Save workout")
        #expect(await scene.probe.calls.count { $0 == .materialize } == 2, "saved once after the one refusal")
    }

    @Test("An end the engine will not take: Try again can never save it; Close, then a new Save workout, does")
    func invalidEnd_tryAgainNeverSaves_asBuilt() async {
        let cover = await Self.askingToEnd()
        await cover.session.holdEveryEnd(false)
        cover.clock.setValue(Date(timeIntervalSinceReferenceDate: .nan))
        cover.send(.save)
        for _ in 0 ..< 3 {
            guard await cover.until("the failure to be shown", { cover.store.dialog == .saveFailed }) else {
                break
            }
            cover.clock.setValue(Self.savedAt)
            cover.send(.retrySave)
        }
        await cover.until("the failure to be shown") { cover.store.dialog == .saveFailed }
        #expect(await cover.session.finishesAsked.count == 4)
        #expect(await cover.session.finishesAsked.allSatisfy { !$0.timeIntervalSinceReferenceDate.isFinite })
        #expect(await cover.session.ended == nil)
        cover.send(.dismissFailure, .finish, .save)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(await cover.session.reached.last == .finished(Self.savedAt))
        #expect(await cover.fault() == nil)
        await cover.close()
    }
}

// MARK: - Refusals, and a queue that leaves nothing to save

extension WorkoutSaveAdversarialTests {
    /// A cover with the first set logged and shown, every change held, and three taps waiting: a log, a
    /// stepper and a log. Returns the number the session gives the first of their calls.
    static func withThreeTapsWaiting() async -> (cover: SaveCover, firstCall: Int) {
        let cover = await SaveCover()
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        let first = await cover.session.nextCall
        await cover.session.holdEveryApply()
        cover.clock.withValue { $0 += 60 }
        cover.tap(
            .log(exerciseIndex: 0, setID: cover.set(0, 1)),
            .stepWeight(exerciseIndex: 1, setID: cover.set(1, 0), .increment),
            .log(exerciseIndex: 1, setID: cover.set(1, 0))
        )
        await cover.until("the first of them to reach the session") { cover.session.waiting.value == 1 }
        return (cover, first)
    }

    @Test("A change refused while the sheet is open: the sheet goes for the alert; after OK, Finish and Save work")
    func refusal_underTheOpenSheet() async {
        let (cover, first) = await Self.withThreeTapsWaiting()
        await cover.session.refuse(calls: [first + 1])
        cover.send(.finish)
        #expect(cover.store.dialog == .finish)
        await cover.session.holdEveryApply(false)
        await cover.session.release()
        await cover.until("the refusal to be shown") { cover.store.dialog == .editFailed }
        await cover.rest()
        #expect(cover.store.queue.isEmpty, "the tap behind the refused one is dropped")
        #expect(await cover.session.reached.count == 2, "the two logs before the refusal, and no more")
        cover.send(.save, .retrySave)
        #expect(!cover.store.isSaving, "nothing is saved from behind the alert")
        #expect(await cover.session.finishesAsked == [])
        cover.send(.dismissFailure)
        cover.clock.withValue { $0 += 60 }
        let tapped = cover.clock.value
        cover.send(.finish, .save)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(await cover.session.reached.last == .finished(tapped))
        #expect(await cover.session.ended?.doneSets == 2)
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("A change refused under a waiting save withdraws it: no finish, the alert, and the next save is a new one")
    func refusal_underAWaitingSave() async {
        let (cover, first) = await Self.withThreeTapsWaiting()
        await cover.session.refuse(calls: [first + 1])
        cover.clock.withValue { $0 += 60 }
        let withdrawn = cover.clock.value
        cover.send(.finish, .save)
        #expect(cover.store.isSaving)
        await cover.session.holdEveryApply(false)
        await cover.session.release()
        await cover.until("the refusal to be shown") { cover.store.dialog == .editFailed }
        await cover.rest()
        #expect(!cover.store.isSaving)
        #expect(cover.store.exit == nil)
        #expect(cover.store.model.header?.isEnabled == true)
        #expect(await cover.session.finishesAsked == [], "never saved without a change the lifter believes was made")
        #expect(await cover.session.reached.count == 2)
        // "Try again" belongs to another alert, and the withdrawn save is not kept for it.
        cover.send(.retrySave)
        #expect(!cover.store.isSaving)
        cover.send(.dismissFailure)
        #expect(cover.store.dialog == nil)
        cover.send(.retrySave)
        #expect(!cover.store.isSaving)
        cover.clock.withValue { $0 += 60 }
        cover.send(.finish, .save)
        await cover.until("the cover to close") { cover.store.exit != nil }
        #expect(await cover.session.finishesAsked == [withdrawn.addingTimeInterval(60)], "the new tap's end")
        #expect(await cover.fault() == nil)
        await cover.close()
    }

    @Test("The last logged set's un-log was waiting at the save: nothing is saved, and the sheet says so")
    func queueLeavesNoSet_nothingIsSaved() async {
        let cover = await SaveCover()
        cover.tap(.log(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the set to be shown as logged") { cover.store.shown?.doneSets == 1 }
        await cover.session.holdEveryApply()
        cover.clock.withValue { $0 += 90 }
        cover.tap(.unlog(exerciseIndex: 0, setID: cover.set(0, 0)))
        await cover.until("the un-log to reach the session") { cover.session.waiting.value == 1 }
        cover.send(.finish)
        #expect(cover.store.finishSheet?.canSave == true, "the page still shows the set")
        cover.send(.save)
        #expect(cover.store.isSaving)
        await cover.session.holdEveryApply(false)
        await cover.session.release()
        await cover.until("the save to be withdrawn") { !cover.store.isSaving }
        await cover.settle()
        #expect(cover.store.dialog == .finish)
        #expect(cover.store.finishSheet?.canSave == false)
        #expect(cover.store.finishSheet?.isEnabled == true, "Discard and Keep lifting answer")
        #expect(cover.store.finishSheet?.summary.hasPrefix("0 of ") == true)
        #expect(await cover.session.finishesAsked == [])
        #expect(await cover.session.current()?.doneSets == 0)
        cover.send(.save)
        #expect(!cover.store.isSaving)
        cover.send(.keepLifting)
        #expect(cover.store.dialog == nil)
        await cover.close()
    }
}
