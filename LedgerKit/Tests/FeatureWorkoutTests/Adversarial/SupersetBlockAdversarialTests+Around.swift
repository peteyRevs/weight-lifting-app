@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// G2, F10 S9: around the block: a member swapped from its legend row, "REMAINING" around a block jumped into
/// from the middle, the rest panel's line in pounds and kilograms, the receipt, a kill mid-round.
extension SupersetBlockAdversarialTests {
    // MARK: Swap inside the block

    @Test("Swapping B: its letter, its rounds and its labels stay; the legend shows the new name and target")
    func swapMember_keepsRoundsAndLabels() throws {
        var walk = Walk(Self.three())
        walk.tap(.jump(exerciseIndex: 1))
        try walk.logTheShownRow() // A1
        let before = try #require(walk.block)
        #expect(before.legend.map { $0.swap != nil } == [false, true, true])
        let choice = SwapChoice(
            replacing: walk.state.exercises[2].exerciseID,
            exerciseID: ExerciseID(EventBuilders.uuid(0xBEEF)),
            name: "Band Pull-Apart",
            replacement: SwappedExercise(
                equipment: .band, step: .pounds(5), load: .pounds(40), lastPerformance: nil
            )
        )
        walk.tap(.swap(exerciseIndex: 2, choice: choice, alsoUpdateProgram: true))
        let after = try #require(walk.block)
        #expect(after.rows.map(\.label) == before.rows.map(\.label))
        #expect(after.rows.map(\.exerciseIndex) == before.rows.map(\.exerciseIndex))
        #expect(after.legend.map(\.letter) == ["A", "B", "C"])
        #expect(after.legend[1].name == "Band Pull-Apart")
        #expect(after.legend[1].target == "1 × 15 @ 40 lb")
        #expect(after.legend[1].swap == "Swap Band Pull-Apart")
        #expect(after.rows[1].summary == "Band Pull-Apart, set 1, 40 pounds, 15 reps")
        #expect(after.steppers?.weightStep == "5 LB", "the shown row is B1, in the band's step")
        #expect(after.title == "Round 1 of 3")
        #expect(try walk.state.programUpdates[#require(walk.state.exercises[2].slotID)] == choice.exerciseID)
        #expect(walk.state.exercises[3].isSupersetWithPrevious, "C still joins the block")
    }

    @Test("A member with a done set has no swap button, and a swap planned for it comes to nothing")
    func swapMember_withADoneSet_refused() throws {
        var walk = Walk(Self.three())
        walk.tap(.jump(exerciseIndex: 1))
        try walk.logTheShownRow() // A1
        let choice = SwapChoice(
            replacing: walk.state.exercises[1].exerciseID,
            exerciseID: ExerciseID(EventBuilders.uuid(0xBEEF)),
            name: "Pull-Up",
            replacement: SwappedExercise(equipment: .bodyweight, step: .pounds(5), load: .zero, lastPerformance: nil)
        )
        let state = walk.state
        walk.tap(.swap(exerciseIndex: 1, choice: choice, alsoUpdateProgram: true))
        let unchanged = walk.state == state
        #expect(unchanged)
    }

    // MARK: REMAINING around a block

    @Test("Jumping into a block's middle from REMAINING: C is shown, no member is listed, earlier ones are, in order")
    func remaining_jumpIntoTheMiddle() throws {
        var walk = Walk(Self.three())
        let listed = try #require(walk.page.remaining?.rows)
        #expect(listed.map(\.name) == ["Lat Pulldown", "Face Pull", "Cable Lateral Raise", "Barbell Curl"])
        let raise = try #require(listed.first { $0.name == "Cable Lateral Raise" })
        walk.tap(.jump(exerciseIndex: raise.exerciseIndex))
        let block = try #require(walk.block)
        #expect(block.legend.map(\.isCurrent) == [false, false, true])
        #expect(block.rows.first { $0.state == .active }?.label == "C1")
        #expect(block.title == "Round 1 of 3")
        #expect(walk.header.progressValue == "Exercise 4 of 5")
        #expect(walk.page.remaining?.rows.map(\.name) == ["Barbell Bench Press", "Barbell Curl"])
        // C1 ends round 1, though A1 and B1 are open: the group's rest starts and the cursor goes on to A2.
        try walk.logTheShownRow()
        #expect(walk.state.rest?.total == .seconds(90))
        #expect(walk.block?.rows.first { $0.state == .active }?.label == "A2")
        #expect(walk.block?.title == "Round 1 of 3", "A1 and B1 are still open")
        #expect(walk.page.remaining?.rows.map(\.name) == ["Barbell Bench Press", "Barbell Curl"])
    }

    @Test("A finished block is never listed under REMAINING; an earlier exercise with a set left is")
    func remaining_finishedBlockNotListed() {
        var state = Self.three()
        for exercise in 1 ... 3 {
            for row in state.exercises[exercise].sets.indices {
                state.exercises[exercise].sets[row].doneAt = Fixtures.now
            }
        }
        state.cursor = Cursor(exerciseIndex: 4, setIndex: 0)
        let page = Cards.page(state)
        #expect(page.card?.title == "Barbell Curl")
        #expect(page.remaining?.rows.map(\.name) == ["Barbell Bench Press"])
    }

    // MARK: The rest panel's line, in pounds and kilograms

    @Test("The rest panel names C2 by its label in pounds and kilograms, spoken with the member's name")
    func restPanel_line_lbAndKg() throws {
        for units in [Units.lb, .kg] {
            var walk = Walk(Self.three(units: units))
            walk.tap(.jump(exerciseIndex: 1))
            for _ in 0 ..< 3 {
                try walk.logTheShownRow() // A1 B1 C1: the group's rest runs
            }
            // While it runs the lifter chooses C2 (a tap on its row): the panel names it.
            let rowC2 = try #require(walk.block?.rows.first { $0.label == "C2" })
            walk.tap(.select(exerciseIndex: rowC2.exerciseIndex, setID: rowC2.id))
            let panel = try #require(WorkoutPresentation.rest(
                walk.state, at: walk.now, selection: walk.selection, isBusy: false, locale: Fixtures.locale
            ))
            let weight = Weight.pounds(15).formatted(in: units)
            let unit = units == .lb ? "lb" : "kg"
            #expect(panel.next?.line == "C2 · \(weight) \(unit) × 15")
            let spokenUnit = units == .lb ? "pounds" : "kilograms"
            #expect(panel.next?.spoken == "Cable Lateral Raise, set 2, \(weight) \(spokenUnit), 15 reps")
        }
    }

    // MARK: The receipt

    @Test("The receipt of a 3-member block workout: one row per exercise, members included, in workout order")
    func receipt_oneRowPerMember() throws {
        var walk = Walk(Self.three())
        walk.tap(.jump(exerciseIndex: 1))
        for _ in 0 ..< 6 {
            try walk.logTheShownRow()
        }
        let finished = try WorkoutPresentationReceiptTests.finished(walk.state, after: 900)
        let rows = WorkoutPresentationReceiptTests.receipt(finished).page.rows
        #expect(rows.map(\.name) == [
            "Barbell Bench Press", "Lat Pulldown", "Face Pull", "Cable Lateral Raise", "Barbell Curl"
        ])
        #expect(rows.count == 5)
    }

    // MARK: Restoration after a kill

    @Test("After a kill mid-round the page the resumed workout draws, with no selection, is the page that was up")
    func restoration_midRound() throws {
        var walk = Walk(Self.three())
        walk.tap(.jump(exerciseIndex: 1))
        try walk.logTheShownRow() // A1
        try walk.logTheShownRow() // B1
        // The lifter chooses A2 out of order (a tap on its row), then steps it.
        let rowA2 = try #require(walk.block?.rows.first { $0.label == "A2" })
        walk.tap(.select(exerciseIndex: rowA2.exerciseIndex, setID: rowA2.id))
        walk.tap(.stepReps(exerciseIndex: rowA2.exerciseIndex, setID: rowA2.id, .increment))
        let before = walk.page
        let resumed = Cards.page(walk.state, selection: nil)
        let same = resumed == before
        #expect(same, "the selection is not kept across a kill; the cursor must name the same row")
        #expect(resumed.block?.rows.first { $0.state == .active }?.label == "A2")
    }
}
