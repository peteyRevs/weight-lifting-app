import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8b, G3 round 1: "Swap exercise" names its exercise (SF1), the swap still opens after a refused one
/// (SF2), a cancelled read shows no failure (N3), and a busy page offers no swap (N6). The fixtures are
/// `WorkoutStoreSwapTests`'.
@MainActor
@Suite("WorkoutStore swap, after review", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSwapReviewTests {
    typealias Swap = WorkoutStoreSwapTests
    typealias Scene = WorkoutScene

    @Test("A tap on Swap exercise opens nothing once the shown exercise moved before its action arrived (SF1)")
    func shownExerciseMoved_opensNothing() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await Swap.following(scene)
        let tapOnBench = store.cardOpensSwap
        store.send(.edit(.jump(exerciseIndex: 1)))
        await store.drain()
        await eventually { store.model.page?.card?.exerciseIndex == 1 }
        store.send(tapOnBench)
        #expect(store.dialog == nil, "another exercise is shown: the tap was not for it")

        store.send(.edit(.jump(exerciseIndex: 0)))
        await store.drain()
        await eventually { store.model.page?.card?.exerciseIndex == 0 }
        let catalog = try ExerciseCatalog.seed()
        let floor = try #require(catalog.first { $0.name == "Barbell Floor Press" })
        try await scene.fake?.apply(.exerciseSwapped(
            exerciseIndex: 0, exerciseID: floor.id, name: floor.name, alsoUpdateProgram: false
        ))
        await eventually { store.model.page?.card?.title == "Barbell Floor Press" }
        store.send(tapOnBench)
        #expect(store.dialog == nil, "the place holds another exercise now")
        store.send(store.cardOpensSwap)
        #expect(store.dialog == .swap, "the card's own tap opens it")
        task.cancel()
    }

    @Test("After a refused swap and its alert, Swap exercise opens the sheet again (SF2)")
    func refusedSwap_thenSwapOpensAgain() async throws {
        let scene = try await Scene.onHost(live: Fixtures.seedSession())
        let (store, task) = await scene.following()
        let row = try await #require(Swap.open(store).rows.first)
        await scene.probe.fail(.append)
        store.send(.edit(row.choose))
        await store.drain()
        #expect(store.dialog == .editFailed)
        store.send(.dismissFailure)
        let reopened = try await Swap.open(store)
        #expect(store.dialog == .swap)
        #expect(reopened.rows.count == 8)
        task.cancel()
    }

    @Test("The refusal's alert waits while the swap sheet is on screen, and shows once it is gone (SF2)")
    func alert_waitsForTheSheet() {
        #expect(!WorkoutRoot.isPresented(.editFailed, dialog: .editFailed, isSwapSheetOnScreen: true))
        #expect(WorkoutRoot.isPresented(.editFailed, dialog: .editFailed, isSwapSheetOnScreen: false))
        #expect(!WorkoutRoot.isPresented(.editFailed, dialog: .swap, isSwapSheetOnScreen: false))
    }

    @Test("A read whose task was cancelled shows no failure, whatever it threw; the next read answers (N3)")
    func cancelledRead_showsNoFailure() async throws {
        let gate = Gate()
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let exercises = SwapExercises(base: scene.stores.exercises, gate: gate, fails: true)
        let (store, task) = await Swap.following(scene) { $0.exerciseRepository = exercises }
        store.send(store.cardOpensSwap)
        let cancelled = Task { await store.loadSwap() }
        await gate.waitForArrival()
        cancelled.cancel()
        await gate.open()
        await cancelled.value
        let held = try #require(store.swapSheet)
        #expect(held.message == nil && held.rows.isEmpty, "still loading, not failed")
        await exercises.heal()
        await store.loadSwap()
        #expect(store.swapSheet?.rows.count == 8)
        task.cancel()
    }

    @Test("While the page answers nothing, no Swap exercise is drawn (N6)")
    func busyPage_offersNoSwap() throws {
        let state = try Fixtures.seedSession()
        let context = WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)
        #expect(WorkoutPresentation.page(state, selection: nil, isBusy: false, context).card?.swap != nil)
        #expect(WorkoutPresentation.page(state, selection: nil, isBusy: true, context).card?.swap == nil)
    }
}
