@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 6 and 16: "REMAINING". After the shown exercise it lists what can still be logged, so
/// that no row leads to a page with nothing to do, each with its sets counted as a target line counts them.
/// The fixtures are `WorkoutPresentationCardTests`'.
@Suite("WorkoutPresentation · what remains", .tags(.feature))
struct WorkoutPresentationRemainingTests {
    typealias Cards = WorkoutPresentationCardTests

    /// Criterion 16: no row of the list leads to a page with nothing to do.
    @Test("REMAINING leaves out a later exercise with every set logged, and one with no set")
    func remaining_listsOnlyWhatCanBeLogged() throws {
        var state = EventBuilders.seedSession()
        for row in state.exercises[2].sets.indices {
            state.exercises[2].sets[row].doneAt = Fixtures.now
        }
        state.exercises[3].sets = []
        state.exercises[4].sets[0].doneAt = Fixtures.now
        let remaining = try #require(Cards.page(state).remaining)
        #expect(remaining.rows.map(\.name) == ["Incline DB Press", "Cable Lateral Raise"])
        // With nothing left after the shown exercise there is no list.
        let last = WorkoutSelection(exerciseIndex: 1, setID: nil)
        state.exercises[4].sets = []
        #expect(Cards.page(state, selection: last).remaining == nil)
    }

    /// Criterion 16: the count is the card's target line's, which does not count a drop set.
    @Test("In REMAINING an exercise's sets are counted without its drop set, and an added set counts")
    func remaining_countsWithoutTheDropSet() throws {
        var state = EventBuilders.session([
            .init("Bench", .barbell, sets: 5, reps: 5, pounds: 185, restSeconds: 150),
            .init("Barbell Curl", .barbell, sets: 3, reps: 12, pounds: 75, restSeconds: 60, dropSet: true)
        ])
        #expect(Cards.page(state).remaining?.rows.map(\.scheme) == ["3 × 12"])
        #expect(try #require(Cards.page(state, selection: WorkoutSelection(exerciseIndex: 1, setID: nil)).card).target
            == "3 × 12 @ 75 lb · RPE 8")
        state.exercises[1].sets.append(LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(75), reps: Reps(clamping: 12), kind: .added
        ))
        #expect(Cards.page(state).remaining?.rows.map(\.scheme) == ["4 × 12"])
    }

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
}
