@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F10 S9, criteria 4 to 13: a superset drawn as one block, word for word. The workout is a bench press, then
/// a superset of Lat Pulldown (A, 3 × 12 @ 100 lb, rest 75 s) and Cable Lateral Raise (B, 3 × 15 @ 15 lb,
/// rest 60 s); sets are logged through the real engine, so the cursor is rule 20's.
@Suite("WorkoutPresentation · a superset's block", .tags(.feature))
struct WorkoutPresentationSupersetTests {
    typealias Cards = WorkoutPresentationCardTests

    static func workout(dropOnB: Bool = false, units: Units = .lb) -> WorkoutState {
        var state = EventBuilders.session([
            .init("Barbell Bench Press", .barbell, sets: 3, reps: 5, pounds: 185, restSeconds: 150),
            .init("Lat Pulldown", .cable, sets: 3, reps: 12, pounds: 100, restSeconds: 75),
            .init(
                "Cable Lateral Raise", .cable, sets: 3, reps: 15, pounds: 15, restSeconds: 60, superset: true,
                dropSet: dropOnB
            )
        ])
        state.units = units
        return state
    }

    /// `state` after `rows` (exercise, set) were logged through the engine, ten seconds apart.
    static func logged(_ rows: [(Int, Int)], in state: WorkoutState) -> WorkoutState {
        var state = state
        for (offset, (exercise, row)) in rows.enumerated() {
            let set = state.exercises[exercise].sets[row]
            let event = WorkoutEvent.setLogged(
                exerciseIndex: exercise, setID: set.id, weight: set.weight, reps: set.reps,
                doneAt: EventBuilders.start.addingTimeInterval(Double(10 * (offset + 1)))
            )
            let envelope = EventBuilders.envelope(event, seq: UInt64(offset + 2), at: EventBuilders.start)
            state = WorkoutEngine.reduce(state, envelope).0 ?? state
        }
        return state
    }

    static func block(
        _ state: WorkoutState,
        selection: WorkoutSelection? = WorkoutSelection(exerciseIndex: 1, setID: nil),
        isBusy: Bool = false
    ) throws -> SupersetBlockModel {
        try #require(Cards.page(state, selection: selection, isBusy: isBusy).block)
    }

    // MARK: Criteria 4 and 5

    @Test("The eyebrow counts blocks, a solo exercise as one: block 2 of 2; Upper A's is block 4 of 4")
    func eyebrow_blockOfBlocks() throws {
        #expect(try Self.block(Self.workout()).eyebrow == "Superset · block 2 of 2")
        let upperA = try Fixtures.seedSession()
        let page = Cards.page(upperA, selection: WorkoutSelection(exerciseIndex: 3, setID: nil))
        #expect(page.block?.eyebrow == "Superset · block 4 of 4")
        // A solo card keeps its own eyebrow.
        #expect(Cards.page(upperA).card?.eyebrow == "Exercise 1 of 5")
    }

    @Test("A one-member block is the solo card, unchanged")
    func oneMemberBlock_isTheSoloCard() {
        var state = Self.workout()
        state.exercises[2].isSupersetWithPrevious = false
        let page = Cards.page(state, selection: WorkoutSelection(exerciseIndex: 2, setID: nil))
        #expect(page.block == nil)
        #expect(page.card?.rows.map(\.label) == ["1", "2", "3"])
        #expect(page.card?.eyebrow == "Exercise 3 of 3")
    }

    // MARK: Criterion 6

    @Test("The round is the first undone row's, of every round; drop rounds count; all done is the last")
    func supersetRoundTitle() throws {
        #expect(try Self.block(Self.workout()).title == "Round 1 of 3")
        let afterRound1 = Self.logged([(0, 0), (1, 0), (2, 0)], in: Self.workout())
        #expect(try Self.block(afterRound1).title == "Round 2 of 3")
        let working = (0 ..< 3).flatMap { [(1, $0), (2, $0)] }
        let dropLeft = Self.logged(working, in: Self.workout(dropOnB: true))
        #expect(try Self.block(dropLeft).title == "Round 4 of 4")
        let allDone = Self.logged(working + [(2, 3)], in: Self.workout(dropOnB: true))
        let block = try Self.block(allDone)
        #expect(block.title == "Round 4 of 4")
        #expect(block.current == nil && block.steppers == nil, "no member is current")
        #expect(block.legend.allSatisfy { !$0.isCurrent })
    }

    // MARK: Criteria 7 and 9

    @Test("The legend: letter, name, target without RPE, in pounds and in kilograms")
    func legend_targets_lbAndKg() throws {
        let pounds = try Self.block(Self.workout())
        #expect(pounds.legend.map(\.letter) == ["A", "B"])
        #expect(pounds.legend.map(\.name) == ["Lat Pulldown", "Cable Lateral Raise"])
        #expect(pounds.legend.map(\.target) == ["3 × 12 @ 100 lb", "3 × 15 @ 15 lb"])
        #expect(pounds.legend.map(\.spoken) == [
            "A, Lat Pulldown, 3 × 12 @ 100 lb", "B, Cable Lateral Raise, 3 × 15 @ 15 lb"
        ])
        let kilograms = try Self.block(Self.workout(units: .kg))
        #expect(kilograms.legend.map(\.target) == ["3 × 12 @ 45.4 kg", "3 × 15 @ 6.8 kg"])
        #expect(kilograms.columns.weight == "kg")
    }

    @Test("After A1 B1 A2 the legend marks B current, and the steppers stand under B2")
    func legend_marksCurrent_BAfterA2() throws {
        let state = Self.logged([(1, 0), (2, 0), (1, 1)], in: Self.workout())
        let block = try Self.block(state)
        #expect(block.legend.map(\.isCurrent) == [false, true])
        #expect(block.steppers?.exerciseIndex == 2 && block.steppers?.setID == state.exercises[2].sets[1].id)
        #expect(block.current?.exerciseIndex == 2)
        #expect(WorkoutPresentation.shownExercise(of: state, selection: nil) == 2)
        #expect(WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale).progressValue
            == "Exercise 3 of 3")
    }

    @Test("Rest 1:15 after B, and its spoken form with the time in words")
    func restLine_andItsSpokenForm() throws {
        let block = try Self.block(Self.workout())
        #expect(block.restLine == "Rest 1:15 after B")
        #expect(block.restLineSpoken == "Rest 1 minute, 15 seconds after B")
    }

    @Test("Each member with no set logged has its swap button; one with a set logged, or a busy page, has none")
    func swap_perMember_noneWithADoneSet() throws {
        let fresh = try Self.block(Self.workout())
        #expect(fresh.legend.map(\.swap) == ["Swap Lat Pulldown", "Swap Cable Lateral Raise"])
        let afterA1 = try Self.block(Self.logged([(1, 0)], in: Self.workout()))
        #expect(afterA1.legend.map(\.swap) == [nil, "Swap Cable Lateral Raise"])
        #expect(try Self.block(Self.workout(), isBusy: true).legend.allSatisfy { $0.swap == nil })
    }
}

// MARK: Criteria 8, 10, 11 and 12

extension WorkoutPresentationSupersetTests {
    @Test("Rows: A1 B1 A2 B2 A3 B3 then BD; an added set after the drop takes the next number, A4")
    func rowLabels_soloDropSuperset() throws {
        var state = Self.workout(dropOnB: true)
        #expect(try Self.block(state).rows.map(\.label) == ["A1", "B1", "A2", "B2", "A3", "B3", "BD"])
        state.exercises[2].sets.append(LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(15), reps: Reps(clamping: 15), kind: .added
        ))
        #expect(try Self.block(state).rows.map(\.label) == ["A1", "B1", "A2", "B2", "A3", "B3", "B4", "BD"])
        // A solo exercise keeps its numbers and its "D".
        let solo = EventBuilders.session([
            .init("Barbell Curl", .barbell, sets: 2, reps: 12, pounds: 75, restSeconds: 60, dropSet: true)
        ])
        #expect(Cards.page(solo).card?.rows.map(\.label) == ["1", "2", "D"])
    }

    @Test("Each row names its member: spoken name first, its check by its label, and its own edits")
    func rows_spokenAndNamed() throws {
        let state = Self.logged([(1, 0)], in: Self.workout(dropOnB: true))
        let block = try Self.block(state)
        #expect(block.rows[0].summary == "Lat Pulldown, set 1, 100 pounds, 12 reps")
        #expect(block.rows[0].checkLabel == "Undo set A1")
        #expect(block.rows[0].check == .unlog(exerciseIndex: 1, setID: state.exercises[1].sets[0].id))
        #expect(block.rows[1].checkLabel == "Log set B1")
        #expect(block.rows[1].check == .log(exerciseIndex: 2, setID: state.exercises[2].sets[0].id))
        #expect(block.rows[6].summary == "Cable Lateral Raise, drop set, 15 pounds, 15 reps")
        #expect(block.rows[6].checkLabel == "Log set BD")
        #expect(block.rows.map(\.exerciseIndex) == [1, 2, 1, 2, 1, 2, 2])
        #expect(block.rows.map(\.state) == [.done, .active, .pending, .pending, .pending, .pending, .pending])
    }

    @Test("The steppers take the shown row's member's step: 5 LB under the bench's row, 2.5 LB under a cable's")
    func steppers_inTheMembersStep() throws {
        var state = Self.workout()
        state.exercises[1].step = .pounds(5)
        let underA = try Self.block(state)
        #expect(underA.steppers?.weightStep == "5 LB")
        #expect(underA.steppers?.weight == "100 pounds" && underA.steppers?.reps == "12 reps")
        let chosenB = WorkoutSelection(exerciseIndex: 2, setID: state.exercises[2].sets[0].id)
        let underB = try Self.block(state, selection: chosenB)
        #expect(underB.steppers?.weightStep == "2.5 LB" && underB.steppers?.exerciseIndex == 2)
    }

    @Test("The current member's Last and Repeat; no Repeat without history; + Add set is the current member's")
    func current_lastAndRepeat() throws {
        var state = Self.workout()
        let august12 = try #require(Fixtures.calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        state.exercises[1].lastPerformance = LastPerformance(date: august12, sets: 3, reps: 12, load: .pounds(95))
        let onA = try Self.block(state)
        #expect(onA.current == SupersetBlockModel.CurrentMember(
            exerciseIndex: 1, lastLabel: "Last", last: "Aug 12 · 3×12 @ 95 lb", repeatLast: "Repeat"
        ))
        #expect(onA.addSet == "+ Add set")
        let onB = try Self.block(
            state,
            selection: WorkoutSelection(exerciseIndex: 2, setID: state.exercises[2].sets[0].id)
        )
        #expect(onB.current == SupersetBlockModel.CurrentMember(
            exerciseIndex: 2, lastLabel: "Last", last: "No history yet", repeatLast: nil
        ))
    }

    @Test("A chosen member with nothing left gives way to the member of the block's first undone row")
    func shownRow_chosenMemberWithNothingLeft_givesWay() throws {
        var state = Self.workout()
        for row in state.exercises[2].sets.indices {
            state.exercises[2].sets[row].doneAt = EventBuilders.start
        }
        let chosenB = WorkoutSelection(exerciseIndex: 2, setID: nil)
        #expect(WorkoutPresentation.shownExercise(of: state, selection: chosenB) == 1)
        let block = try Self.block(state, selection: chosenB)
        #expect(block.legend.map(\.isCurrent) == [true, false])
        #expect(block.steppers?.setID == state.exercises[1].sets[0].id)
        // The engine's cursor in the block wins over its first undone row.
        state.cursor = Cursor(exerciseIndex: 1, setIndex: 2)
        #expect(try Self.block(state, selection: chosenB).steppers?.setID == state.exercises[1].sets[2].id)
    }
}
