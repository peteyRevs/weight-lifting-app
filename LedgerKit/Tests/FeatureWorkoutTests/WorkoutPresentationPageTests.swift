@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 6 and 12: which exercise and which row the page shows, the list of those remaining, and
/// that every workout gives a page. The fixtures are `WorkoutPresentationCardTests`'.
@Suite("WorkoutPresentation · the shown exercise, and what remains", .tags(.feature))
struct WorkoutPresentationPageTests {
    typealias Cards = WorkoutPresentationCardTests

    // MARK: Which exercise and which row are shown

    @Test("With nothing chosen the card is the cursor's exercise and its shown row the cursor's")
    func shown_followsTheCursor() throws {
        var state = EventBuilders.seedSession()
        state.cursor = Cursor(exerciseIndex: 2, setIndex: 3)
        let card = try #require(Cards.page(state).card)
        #expect(card.eyebrow == "Exercise 3 of 5")
        #expect(card.title == "Chest-Supported Row")
        #expect(card.rows.map(\.state) == [.pending, .pending, .pending, .active])
        #expect(card.steppers?.setID == Cards.set(2, 3))
    }

    @Test("The header and the card name the same exercise, chosen or not")
    func shown_headerAndCardAgree() throws {
        let state = EventBuilders.seedSession()
        for selection in [nil, WorkoutSelection(exerciseIndex: 3, setID: nil)] {
            let header = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale, selection: selection)
            let card = try #require(Cards.page(state, selection: selection).card)
            #expect(header.progressValue == card.eyebrow)
            let current = header.segments.firstIndex { $0.state == .current }
            #expect(current == card.exerciseIndex)
        }
    }

    @Test(
        "The cursor on a finished exercise: the first exercise with a set to log is shown, at its first open row"
    )
    func shown_cursorOnAFinishedExercise_showsTheFirstUnfinished() throws {
        var state = EventBuilders.seedSession()
        for row in state.exercises[3].sets.indices {
            state.exercises[3].sets[row].doneAt = Fixtures.now
        }
        state.exercises[0].sets[0].doneAt = Fixtures.now
        state.cursor = Cursor(exerciseIndex: 3, setIndex: 2)
        let card = try #require(Cards.page(state).card)
        #expect(card.title == "Barbell Bench Press")
        #expect(card.rows.map(\.state) == [.done, .active, .pending, .pending, .pending])
    }

    @Test("A logged row is never the shown row: with every set of the exercise logged there are no steppers")
    func shown_everySetLogged_hasNoSteppers() throws {
        var state = EventBuilders.session([.init("Lift", .barbell, sets: 2, reps: 5, pounds: 100, restSeconds: 90)])
        state.exercises[0].sets[0].doneAt = Fixtures.now
        state.exercises[0].sets[1].doneAt = Fixtures.now
        state.cursor = Cursor(exerciseIndex: 0, setIndex: 1)
        let card = try #require(Cards.page(state).card)
        #expect(card.rows.map(\.state) == [.done, .done])
        #expect(card.steppers == nil)
        #expect(Cards.page(state).remaining == nil)
    }

    @Test("A chosen row that has since been logged gives way to the exercise's first open row")
    func shown_chosenRowLogged_fallsToTheFirstOpenRow() throws {
        var state = EventBuilders.seedSession()
        state.exercises[1].sets[1].doneAt = Fixtures.now
        let chosen = WorkoutSelection(exerciseIndex: 1, setID: Cards.set(1, 1))
        #expect(try #require(Cards.page(state, selection: chosen).card).rows.map(\.state) == [.active, .done, .pending])
    }

    // MARK: Criterion 6: remaining

    @Test("REMAINING lists the exercises after the shown one, each with its rows and the reps of its first")
    func remaining_listsTheLaterExercises() throws {
        var state = EventBuilders.seedSession()
        state.exercises[3].sets.append(
            LoggedSet(
                id: SetID(EventBuilders.uuid(0xADD)),
                weight: .pounds(100),
                reps: Reps(clamping: 12),
                kind: .added
            )
        )
        let chosen = WorkoutSelection(exerciseIndex: 1, setID: nil)
        let remaining = try #require(Cards.page(state, selection: chosen).remaining)
        #expect(remaining.title == "REMAINING")
        #expect(remaining.rows.map(\.name) == ["Chest-Supported Row", "Lat Pulldown", "Cable Lateral Raise"])
        #expect(remaining.rows.map(\.scheme) == ["4 × 8", "4 × 12", "3 × 15"])
        #expect(remaining.rows.map(\.exerciseIndex) == [2, 3, 4])
    }

    @Test("On the last exercise nothing remains")
    func remaining_lastExercise_isNil() {
        let last = WorkoutSelection(exerciseIndex: 4, setID: nil)
        #expect(Cards.page(EventBuilders.seedSession(), selection: last).remaining == nil)
    }

    @Test("While a discard runs the page's controls are off, as the header's are")
    func page_busy_isNotEnabled() {
        #expect(Cards.page(EventBuilders.seedSession(), isBusy: true).isEnabled == false)
        #expect(Cards.page(EventBuilders.seedSession()).isEnabled)
    }

    // MARK: Criterion 12: total

    @Test("A workout with no exercise gives a page with no card and nothing remaining")
    func page_noExercise_isEmpty() {
        let page = Cards.page(EventBuilders.session([]))
        #expect(page.card == nil)
        #expect(page.remaining == nil)
    }

    @Test("An exercise with no set gives a card with its words and no row")
    func card_noSet_hasNoRow() throws {
        var state = EventBuilders.seedSession()
        state.exercises[1].sets = []
        let card = try #require(Cards.page(state, selection: WorkoutSelection(exerciseIndex: 1, setID: nil)).card)
        #expect(card.title == "Incline DB Press")
        #expect(card.target == "3 × 10 @ 55 lb · RPE 8")
        #expect(card.rows.isEmpty)
        #expect(card.steppers == nil)
        // In the list of those still to come it reads its target's reps, having no first set.
        #expect(Cards.page(state).remaining?.rows.first?.scheme == "0 × 10")
    }

    @Test(
        "A cursor that names no row, or none at all, gives no card, and every exercise can be reached from REMAINING",
        arguments: [
            Cursor?.none, Cursor(exerciseIndex: 5, setIndex: 0), Cursor(exerciseIndex: 0, setIndex: 5),
            Cursor(exerciseIndex: -1, setIndex: 0), Cursor(exerciseIndex: .max, setIndex: .max)
        ]
    )
    func page_cursorNamesNoRow_listsEveryExercise(cursor: Cursor?) {
        var state = EventBuilders.seedSession()
        state.cursor = cursor
        let page = Cards.page(state)
        #expect(page.card == nil)
        #expect(page.remaining?.rows.map(\.exerciseIndex) == [0, 1, 2, 3, 4])
    }

    @Test("A choice that names an exercise or a set the workout does not hold falls back to the cursor", arguments: [
        WorkoutSelection(exerciseIndex: 9, setID: nil), WorkoutSelection(exerciseIndex: -1, setID: nil),
        WorkoutSelection(exerciseIndex: 0, setID: EventBuilders.setID(3, 0))
    ])
    func page_choiceNamesNothing_fallsBack(selection: WorkoutSelection) throws {
        let card = try #require(Cards.page(EventBuilders.seedSession(), selection: selection).card)
        #expect(card.title == "Barbell Bench Press")
        #expect(card.rows.first?.state == .active)
    }

    @Test("An exercise the catalog no longer holds is drawn from what the workout holds of it")
    func card_exerciseNotStored_isDrawnFromTheWorkout() throws {
        var state = EventBuilders.seedSession()
        state.exercises[0].exerciseID = ExerciseID(EventBuilders.uuid(0xDEAD))
        state.exercises[0].slotID = nil
        state.exercises[0].name = ""
        let card = try #require(Cards.page(state).card)
        #expect(card.title.isEmpty)
        #expect(card.rows.count == 5)
    }
}
