@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F10 S9, criteria 9, 10, 15, 17 and 18: around a superset's block. The rest panel's line names the block's
/// row, a stepper on another member's row selects it first, a legend jump to a finished member changes no
/// shown row, the receipt lists the members as rows of their own, and a member that is not the shown one is
/// swapped from its legend row. The workout is `WorkoutPresentationSupersetTests`'.
@MainActor
@Suite("Around a superset's block", .tags(.feature))
struct WorkoutSupersetAroundTests {
    typealias Block = WorkoutPresentationSupersetTests
    typealias Cards = WorkoutPresentationCardTests

    static func panel(_ state: WorkoutState, selection: WorkoutSelection? = nil) -> RestPanelModel? {
        WorkoutPresentation.rest(
            state, at: EventBuilders.start.addingTimeInterval(30), selection: selection, isBusy: false,
            locale: Fixtures.locale
        )
    }

    // MARK: Criterion 15: the rest panel's line

    @Test("After B1 the rest panel names A2 by its label, spoken with the member's name")
    func restLine_namesTheBlocksRow() throws {
        let state = Block.logged([(0, 0), (0, 1), (0, 2), (1, 0), (2, 0)], in: Block.workout())
        let next = try #require(Self.panel(state)?.next)
        #expect(next.line == "A2 · 100 lb × 12")
        #expect(next.spoken == "Lat Pulldown, set 2, 100 pounds, 12 reps")
        let kilograms = Block.logged([(0, 0), (0, 1), (0, 2), (1, 0), (2, 0)], in: Block.workout(units: .kg))
        #expect(Self.panel(kilograms)?.next?.line == "A2 · 45.4 kg × 12")
    }

    @Test("A drop row is named AD on the rest panel; a solo set keeps Set n")
    func restLine_dropRow_andSolo() {
        var state = Block.workout()
        state.exercises[1].sets.append(LoggedSet(
            id: SetID(EventBuilders.uuid(0xD0)), weight: .pounds(85), reps: Reps(clamping: 12), kind: .drop
        ))
        let rows = (0 ..< 3).flatMap { [(1, $0), (2, $0)] }
        let atTheDrop = Block.logged([(0, 0), (0, 1), (0, 2)] + rows, in: state)
        #expect(Self.panel(atTheDrop)?.next?.line == "AD · 85 lb × 12")
        #expect(Self.panel(atTheDrop)?.next?.spoken == "Lat Pulldown, drop set, 85 pounds, 12 reps")
        let solo = Block.logged([(0, 0)], in: Block.workout())
        #expect(Self.panel(solo)?.next?.line == "Set 2 · 185 lb × 5")
    }

    // MARK: Criteria 10 and 18: taps on the block's rows

    @Test("A stepper on B's row while A's is shown selects B's row first, then changes it")
    func stepOnB_whileAShown_selectsB() {
        let state = Block.logged([(0, 0), (0, 1), (0, 2)], in: Block.workout())
        let rowB = state.exercises[2].sets[0].id
        #expect(WorkoutPresentation.shownExercise(of: state, selection: nil) == 1)
        let plan = WorkoutEditPlan.make(
            .stepReps(exerciseIndex: 2, setID: rowB, .increment), in: state, selection: nil, now: Fixtures.now
        ) { SetID(EventBuilders.uuid(0xADD)) }
        #expect(plan.events == [
            .exerciseSelected(exerciseIndex: 2, setIndex: 0),
            .setTargetChanged(exerciseIndex: 2, setID: rowB, weight: nil, reps: Reps(clamping: 16))
        ])
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 2, setID: rowB))
    }

    @Test("A legend tap on a finished member leaves the shown row where it was")
    func legendJump_toAFinishedMember_leavesTheShownRow() throws {
        var state = Block.logged([(0, 0), (0, 1), (0, 2), (1, 0), (2, 0), (1, 1), (2, 1), (2, 2)], in: Block.workout())
        state.cursor = Cursor(exerciseIndex: 1, setIndex: 2)
        let before = try Block.block(state, selection: nil)
        let plan = WorkoutEditPlan.make(.jump(exerciseIndex: 2), in: state, selection: nil, now: Fixtures.now) {
            SetID(EventBuilders.uuid(0xADD))
        }
        #expect(plan.events.isEmpty)
        let after = try Block.block(state, selection: plan.selection)
        #expect(after.steppers == before.steppers)
        #expect(after.legend.map(\.isCurrent) == [true, false])
    }

    /// F10-S9-G2-1: a member is jumped to at its first open row in the block's order; a solo exercise keeps
    /// its set order, so its drop set still comes before a set added after it.
    @Test("A jump to a member takes the block's order (B4 before BD); a solo jump keeps set order")
    func jump_memberInDisplayOrder_soloInSetOrder() {
        var state = Block.workout(dropOnB: true)
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(15), reps: Reps(clamping: 15), kind: .added
        )
        state.exercises[2].sets.append(added)
        let done = Block.logged([(0, 0), (0, 1), (0, 2), (1, 0), (2, 0), (1, 1), (2, 1), (1, 2), (2, 2)], in: state)
        // From the bench press's card ("REMAINING"): with B shown, its legend tap would change nothing (N5).
        let fromBench = WorkoutSelection(exerciseIndex: 0, setID: nil)
        let plan = WorkoutEditPlan.make(.jump(exerciseIndex: 2), in: done, selection: fromBench, now: Fixtures.now) {
            SetID(EventBuilders.uuid(0xADE))
        }
        #expect(plan.events == [.exerciseSelected(exerciseIndex: 2, setIndex: 4)])
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 2, setID: added.id))
        var solo = state
        solo.exercises[2].isSupersetWithPrevious = false
        let soloDone = Block.logged([(2, 0), (2, 1), (2, 2)], in: solo)
        let soloPlan = WorkoutEditPlan.make(.jump(exerciseIndex: 2), in: soloDone, selection: nil, now: Fixtures.now) {
            SetID(EventBuilders.uuid(0xADE))
        }
        #expect(soloPlan.events == [.exerciseSelected(exerciseIndex: 2, setIndex: 3)], "the drop set, in set order")
    }
}

// MARK: Review SF1, N5 and SF2: legend taps and the shown place

extension WorkoutSupersetAroundTests {
    static func plan(_ edit: WorkoutEdit, in state: WorkoutState, selection: WorkoutSelection?) -> WorkoutEditPlan {
        WorkoutEditPlan.make(edit, in: state, selection: selection, now: Fixtures.now) {
            SetID(EventBuilders.uuid(0xADE))
        }
    }

    /// Review SF1: A3 chosen, B finished; B's legend row changes nothing, and A3 keeps its steppers.
    @Test("A legend tap on a finished member keeps a chosen row, and its steppers")
    func legendTap_finishedMember_keepsTheChosenRow() throws {
        let state = Block.logged([(0, 0), (0, 1), (0, 2), (1, 0), (2, 0), (1, 1), (2, 1), (2, 2)], in: Block.workout())
        let chosen = WorkoutSelection(exerciseIndex: 1, setID: state.exercises[1].sets[2].id)
        let plan = Self.plan(.jump(exerciseIndex: 2), in: state, selection: chosen)
        #expect(plan.events.isEmpty)
        #expect(plan.selection == chosen)
        #expect(try Block.block(state, selection: plan.selection).steppers?.setID == chosen.setID)
    }

    /// Review SF1: with every row of the block logged, a legend tap on the other member moves no segment.
    @Test("In a finished block a legend tap on the other member changes neither the selection nor the header")
    func legendTap_finishedBlock_headerStays() {
        let rows = (0 ..< 3).flatMap { [(1, $0), (2, $0)] }
        let state = Block.logged(rows, in: Block.workout())
        let onA = WorkoutSelection(exerciseIndex: 1, setID: nil)
        let before = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale, selection: onA)
        let plan = Self.plan(.jump(exerciseIndex: 2), in: state, selection: onA)
        #expect(plan.events.isEmpty)
        #expect(plan.selection == onA)
        let after = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale, selection: plan.selection)
        #expect(after.progressValue == before.progressValue && after.segments == before.segments)
    }

    /// Review SF1: "REMAINING" lists a finished member only when nothing is shown; its tap shows the block.
    @Test("With nothing shown, a REMAINING tap on a finished member shows its block")
    func remainingTap_finishedMember_nothingShown_showsTheBlock() {
        var state = Block.logged([(2, 0), (2, 1), (2, 2)], in: Block.workout())
        state.cursor = nil
        #expect(WorkoutPresentation.shownExercise(of: state, selection: nil) == nil)
        let plan = Self.plan(.jump(exerciseIndex: 2), in: state, selection: nil)
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 2, setID: nil))
        #expect(Cards.page(state, selection: plan.selection).block != nil)
    }

    /// Review N5: a legend tap on the member that holds the shown row changes nothing, a chosen row included.
    @Test("A legend tap on the current member keeps the row the lifter chose")
    func legendTap_currentMember_isNoOp() {
        let state = Block.logged([(1, 0), (2, 0)], in: Block.workout())
        let chosen = WorkoutSelection(exerciseIndex: 1, setID: state.exercises[1].sets[2].id)
        let plan = Self.plan(.jump(exerciseIndex: 1), in: state, selection: chosen)
        #expect(plan.events.isEmpty)
        #expect(plan.selection == chosen)
        // The other member is still jumped to.
        let toB = Self.plan(.jump(exerciseIndex: 2), in: state, selection: chosen)
        #expect(toB.events == [.exerciseSelected(exerciseIndex: 2, setIndex: 1)])
    }

    /// Review SF2: the page scrolls to its top when its shown place changes: a card's exercise, a block's
    /// first member.
    @Test("The shown place is the card's exercise or the block's first member, whichever member is current")
    func shownPlace_cardOrBlocksFirstMember() {
        let state = Block.workout()
        #expect(Cards.page(state).shownPlace == 0)
        let onA = Cards.page(state, selection: WorkoutSelection(exerciseIndex: 1, setID: nil))
        let onB = Cards.page(state, selection: WorkoutSelection(exerciseIndex: 2, setID: state.exercises[2].sets[0].id))
        #expect(onA.block?.legend.first { $0.isCurrent }?.exerciseIndex == 1)
        #expect(onB.block?.legend.first { $0.isCurrent }?.exerciseIndex == 2)
        #expect(onA.shownPlace == 1 && onB.shownPlace == 1)
    }
}

// MARK: Criteria 17 and 9

extension WorkoutSupersetAroundTests {
    // MARK: Criterion 17: the receipt

    @Test("The receipt lists a superset's members as rows of their own, in workout order, with their chips")
    func receipt_supersetWorkout_oneRowPerMember() throws {
        let state = Block.logged([(0, 0), (1, 0), (2, 0)], in: Block.workout())
        let finished = try WorkoutPresentationReceiptTests.finished(state, after: 600)
        let receipt = WorkoutPresentationReceiptTests.receipt(finished)
        let rows = receipt.page.rows
        #expect(rows.map(\.name) == ["Barbell Bench Press", "Lat Pulldown", "Cable Lateral Raise"])
        #expect(rows.map(\.chips) == [["185×5"], ["100×12"], ["15×15"]])
        #expect(receipt.rowActions.count == 3)
    }

    // MARK: Criterion 9: swap from the legend

    @Test("A member that is not the shown one opens its own swap sheet from its legend row")
    func swap_fromAMemberThatIsNotShown() async throws {
        let running = try Fixtures.seedSession()
        let scene = try WorkoutScene.onFake(live: running)
        let (store, task) = await WorkoutStoreSwapTests.following(scene)
        store.send(.edit(.jump(exerciseIndex: 3)))
        await store.drain()
        let block = try #require(store.model.page?.block)
        #expect(block.legend.map(\.isCurrent) == [true, false])
        let raise = try #require(block.legend.last)
        store.send(.swap(.open(exerciseIndex: raise.exerciseIndex, exerciseID: raise.exerciseID)))
        await store.loadSwap()
        #expect(store.dialog == .swap)
        #expect(store.swap?.exerciseIndex == 4)
        let row = try #require(store.swapSheet?.rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        let live = try #require(try await scene.session.current())
        #expect(live.exercises[4].exerciseID == row.id)
        #expect(live.exercises[3].exerciseID == running.exercises[3].exerciseID)
        // A place outside the shown block opens nothing.
        store.send(.swap(.open(exerciseIndex: 0, exerciseID: running.exercises[0].exerciseID)))
        #expect(store.dialog == nil)
        task.cancel()
    }
}
