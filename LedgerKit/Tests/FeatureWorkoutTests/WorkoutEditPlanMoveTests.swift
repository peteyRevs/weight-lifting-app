@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 5, 6 and 12: what "Repeat", "+ Add set", a row of "REMAINING" and a tap on a row come to,
/// and that an edit naming nothing comes to nothing. The fixtures are `WorkoutEditPlanTests`'.
@Suite("WorkoutEditPlan · repeat, add, jump and select", .tags(.feature))
struct WorkoutEditPlanMoveTests {
    typealias Plans = WorkoutEditPlanTests

    // MARK: Criterion 5: repeat and add

    @Test("Repeat gives every set of the exercise the last workout's weight and reps, in one event")
    func repeatLast_writesTheLastWorkout() {
        var state = Plans.seed
        state.exercises[1].lastPerformance = LastPerformance(
            date: Fixtures.now.addingTimeInterval(-86400), sets: 3, reps: 9, load: .pounds(52.5)
        )
        #expect(Plans.plan(.repeatLast(exerciseIndex: 1), in: state).events == [
            .allSetsRepeated(exerciseIndex: 1, weight: .pounds(52.5), reps: Reps(clamping: 9))
        ])
        #expect(Plans.plan(.repeatLast(exerciseIndex: 0), in: state).events == [], "no last workout, nothing to repeat")
    }

    @Test("Add set appends a copy of the last row's weight and reps under a new id, and is no drop set")
    func addSet_copiesTheLastRow() {
        var state = EventBuilders.session([
            .init("Curl", .barbell, sets: 2, reps: 12, pounds: 75, restSeconds: 60, dropSet: true)
        ])
        state.exercises[0].sets[2].weight = .pounds(65)
        state.exercises[0].sets[2].reps = Reps(clamping: 10)
        let plan = Plans.plan(.addSet(exerciseIndex: 0), in: state)
        #expect(plan.events == [.setAdded(
            exerciseIndex: 0,
            set: LoggedSet(id: Plans.newID, weight: .pounds(65), reps: Reps(clamping: 10), kind: .added)
        )])
        #expect(plan.selection == nil)
    }

    @Test("Add set on an exercise with no row adds 0 × 8 (spec §3.7)")
    func addSet_noRow_addsZeroByEight() {
        var state = Plans.seed
        state.exercises[1].sets = []
        #expect(Plans.plan(.addSet(exerciseIndex: 1), in: state).events == [.setAdded(
            exerciseIndex: 1,
            set: LoggedSet(id: Plans.newID, weight: .zero, reps: Reps(clamping: 8), kind: .added)
        )])
    }

    // MARK: Criterion 6: jumping, and selecting a row

    @Test("A row of REMAINING shows that exercise at its first set that is not logged")
    func jump_showsTheFirstOpenRow() {
        let state = Plans.logged([0, 1], of: 2)
        let plan = Plans.plan(.jump(exerciseIndex: 2), in: state)
        #expect(plan.events == [.exerciseSelected(exerciseIndex: 2, setIndex: 2)])
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 2, setID: Plans.set(2, 2)))
    }

    @Test("Jumping to an exercise with every set logged, or with none, shows it with no row chosen and sends nothing")
    func jump_nothingToLog_showsTheExercise() {
        let done = Plans.logged([0, 1, 2], of: 1)
        let plan = Plans.plan(.jump(exerciseIndex: 1), in: done)
        #expect(plan.events == [])
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 1, setID: nil))
        var empty = Plans.seed
        empty.exercises[3].sets = []
        #expect(Plans.plan(.jump(exerciseIndex: 3), in: empty).selection == WorkoutSelection(
            exerciseIndex: 3,
            setID: nil
        ))
    }

    @Test("A tap on a row that is not logged makes it the shown row, here and for the engine's cursor")
    func select_openRow_selects() {
        let plan = Plans.plan(.select(exerciseIndex: 0, setID: Plans.set(0, 2)))
        #expect(plan.events == [.exerciseSelected(exerciseIndex: 0, setIndex: 2)])
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 0, setID: Plans.set(0, 2)))
    }

    @Test("A tap on a logged row selects nothing")
    func select_loggedRow_comesToNothing() {
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Plans.set(0, 2))
        let plan = Plans.plan(
            .select(exerciseIndex: 0, setID: Plans.set(0, 0)),
            in: Plans.logged([0], of: 0),
            selection: chosen
        )
        #expect(plan.events == [])
        #expect(plan.selection == chosen)
    }

    // MARK: Criterion 12: total

    @Test("An edit that names an exercise or a set the workout does not hold comes to nothing", arguments: [
        WorkoutEdit.select(exerciseIndex: 9, setID: EventBuilders.setID(0, 0)),
        .select(exerciseIndex: 0, setID: EventBuilders.setID(1, 0)),
        .log(exerciseIndex: -1, setID: EventBuilders.setID(0, 0)),
        .log(exerciseIndex: 0, setID: EventBuilders.setID(4, 2)),
        .unlog(exerciseIndex: 5, setID: EventBuilders.setID(0, 0)),
        .stepWeight(exerciseIndex: 5, setID: EventBuilders.setID(0, 0), .increment),
        .stepReps(exerciseIndex: 0, setID: EventBuilders.setID(3, 0), .decrement),
        .repeatLast(exerciseIndex: 5), .addSet(exerciseIndex: 5), .addSet(exerciseIndex: -1),
        .jump(exerciseIndex: 5), .jump(exerciseIndex: -1)
    ])
    func edit_namingNothing_comesToNothing(edit: WorkoutEdit) {
        let chosen = WorkoutSelection(exerciseIndex: 1, setID: Plans.set(1, 1))
        for state in [Plans.seed, EventBuilders.session([])] {
            let plan = Plans.plan(edit, in: state, selection: chosen)
            #expect(plan.events == [])
            #expect(plan.selection == chosen)
        }
    }
}
