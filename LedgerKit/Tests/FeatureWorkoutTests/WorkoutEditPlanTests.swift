@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 3 to 6: what each tap on the page comes to, as events for the session and the row shown
/// afterwards. `WorkoutEditPlan.make` is pure: the workout, the selection, the time and the new set's id are
/// arguments. What the engine then does with the events is the engine's (`LedgerDomainTests`), and what the
/// store does with a plan is `WorkoutStorePumpTests`'.
@Suite("WorkoutEditPlan", .tags(.feature))
struct WorkoutEditPlanTests {
    /// Bench 5 × 5 @ 185 lb (barbell, 5 lb steps), then four more exercises; the cursor on (0, 0).
    static let seed = EventBuilders.seedSession()
    static let newID = SetID(EventBuilders.uuid(0xADD))

    static func set(_ exercise: Int, _ row: Int) -> SetID {
        EventBuilders.setID(exercise, row)
    }

    static func plan(
        _ edit: WorkoutEdit,
        in state: WorkoutState = seed,
        selection: WorkoutSelection? = nil
    ) -> WorkoutEditPlan {
        WorkoutEditPlan.make(edit, in: state, selection: selection, now: Fixtures.now) { newID }
    }

    /// `state` with the rows `rows` of exercise `exercise` logged.
    static func logged(_ rows: [Int], of exercise: Int, in state: WorkoutState = seed) -> WorkoutState {
        var state = state
        for row in rows {
            state.exercises[exercise].sets[row].doneAt = Fixtures.now
        }
        return state
    }

    /// One exercise of `equipment` with its Domain step in `units`, one set at `weight` × `reps`.
    static func single(_ equipment: Equipment, _ units: Units, weight: Weight, reps: Int = 5) -> WorkoutState {
        var state = EventBuilders.session([
            .init("Lift", equipment, sets: 1, reps: reps, pounds: 0, restSeconds: 90)
        ])
        state.units = units
        state.exercises[0].step = equipment.defaultStep(in: units)
        state.exercises[0].sets[0].weight = weight
        return state
    }

    // MARK: Criterion 3: logging

    @Test(
        "The check of an open row logs it as the row reads, at the time given; the engine picks the next row"
    )
    func log_openRow_logsWhatTheRowReads() {
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Self.set(0, 1))
        let plan = Self.plan(.log(exerciseIndex: 0, setID: Self.set(0, 1)), selection: chosen)
        #expect(plan.events == [.setLogged(
            exerciseIndex: 0,
            setID: Self.set(0, 1),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: Fixtures.now
        )])
        #expect(plan.selection == nil, "rule 20: the engine's cursor says which row is next")
    }

    @Test("A second tap on the check of a row that was drawn open finds it logged and does nothing")
    func log_rowAlreadyLogged_comesToNothing() {
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Self.set(0, 1))
        let plan = Self.plan(
            .log(exerciseIndex: 0, setID: Self.set(0, 0)),
            in: Self.logged([0], of: 0),
            selection: chosen
        )
        #expect(plan.events == [])
        #expect(plan.selection == chosen)
    }

    @Test("The check of a logged row un-logs it and moves nothing")
    func unlog_loggedRow_unlogsAndKeepsTheSelection() {
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Self.set(0, 3))
        let state = Self.logged([0, 1], of: 0)
        let plan = Self.plan(.unlog(exerciseIndex: 0, setID: Self.set(0, 1)), in: state, selection: chosen)
        #expect(plan.events == [.setUnlogged(exerciseIndex: 0, setID: Self.set(0, 1))])
        #expect(plan.selection == chosen)
        #expect(Self.plan(.unlog(exerciseIndex: 0, setID: Self.set(0, 2)), in: state).events == [])
    }

    // MARK: Criterion 4: steppers

    @Test("One tap on the weight moves it by the Domain's step for the equipment and the unit", arguments: [
        (Equipment.barbell, Units.lb, Weight.pounds(5)), (.kettlebell, .lb, .pounds(5)), (.dumbbell, .lb, .pounds(2.5)),
        (.machine, .lb, .pounds(2.5)), (.barbell, .kg, .kilograms(2.5)), (.kettlebell, .kg, .kilograms(2)),
        (.cable, .kg, .kilograms(1.25)), (.bodyweight, .kg, .kilograms(1.25))
    ])
    func stepWeight_movesByTheDomainsStep(equipment: Equipment, units: Units, step: Weight) {
        let start = step + step + step
        let state = Self.single(equipment, units, weight: start)
        let row = Self.set(0, 0)
        let more = Self.plan(.stepWeight(exerciseIndex: 0, setID: row, .increment), in: state)
        #expect(more.events == [
            .setTargetChanged(exerciseIndex: 0, setID: row, weight: start + step, reps: nil)
        ])
        let less = Self.plan(.stepWeight(exerciseIndex: 0, setID: row, .decrement), in: state)
        #expect(less.events == [
            .setTargetChanged(exerciseIndex: 0, setID: row, weight: start - step, reps: nil)
        ])
    }

    @Test("The weight never goes under zero: a step that would is held at zero, and at zero \"−\" sends nothing")
    func stepWeight_neverUnderZero() {
        let row = Self.set(0, 0)
        let low = Self.single(.barbell, .lb, weight: .pounds(2.5))
        #expect(Self.plan(.stepWeight(exerciseIndex: 0, setID: row, .decrement), in: low).events == [
            .setTargetChanged(exerciseIndex: 0, setID: row, weight: .zero, reps: nil)
        ])
        let none = Self.single(.barbell, .lb, weight: .zero)
        #expect(Self.plan(.stepWeight(exerciseIndex: 0, setID: row, .decrement), in: none).events == [])
        #expect(Self.plan(.stepWeight(exerciseIndex: 0, setID: row, .increment), in: none).events == [
            .setTargetChanged(exerciseIndex: 0, setID: row, weight: .pounds(5), reps: nil)
        ])
    }

    @Test("Reps move by one and never go under one")
    func stepReps_movesByOne_neverUnderOne() {
        let row = Self.set(0, 0)
        let five = Self.single(.barbell, .lb, weight: .pounds(100), reps: 5)
        #expect(Self.plan(.stepReps(exerciseIndex: 0, setID: row, .increment), in: five).events == [
            .setTargetChanged(exerciseIndex: 0, setID: row, weight: nil, reps: Reps(clamping: 6))
        ])
        #expect(Self.plan(.stepReps(exerciseIndex: 0, setID: row, .decrement), in: five).events == [
            .setTargetChanged(exerciseIndex: 0, setID: row, weight: nil, reps: Reps(clamping: 4))
        ])
        let one = Self.single(.barbell, .lb, weight: .pounds(100), reps: 1)
        #expect(Self.plan(.stepReps(exerciseIndex: 0, setID: row, .decrement), in: one).events == [])
    }

    @Test("A stepper on the shown row changes that set alone and selects nothing")
    func step_onTheShownRow_changesOnlyThatSet() {
        // The cursor is on (0, 0): with nothing chosen that is the shown row.
        let plan = Self.plan(.stepWeight(exerciseIndex: 0, setID: Self.set(0, 0), .increment))
        #expect(plan.events == [
            .setTargetChanged(exerciseIndex: 0, setID: Self.set(0, 0), weight: .pounds(190), reps: nil)
        ])
        #expect(plan.selection == nil)
    }

    @Test("A stepper on a row that is not the shown one selects it first, then changes it", arguments: [
        WorkoutEdit.stepWeight(exerciseIndex: 0, setID: EventBuilders.setID(0, 3), .increment),
        .stepReps(exerciseIndex: 0, setID: EventBuilders.setID(0, 3), .increment)
    ])
    func step_onAnotherRow_selectsItFirst(edit: WorkoutEdit) {
        let plan = Self.plan(edit)
        #expect(plan.events.first == .exerciseSelected(exerciseIndex: 0, setIndex: 3))
        #expect(plan.events.count == 2)
        guard case let .setTargetChanged(exerciseIndex, setID, _, _)? = plan.events.last else {
            Issue.record("the second event is not the change")
            return
        }
        #expect(exerciseIndex == 0)
        #expect(setID == Self.set(0, 3))
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 0, setID: Self.set(0, 3)))
    }

    @Test("A stepper on a row of another exercise selects that row first")
    func step_onAnotherExercise_selectsItFirst() {
        let plan = Self.plan(.stepReps(exerciseIndex: 2, setID: Self.set(2, 0), .decrement))
        #expect(plan.events == [
            .exerciseSelected(exerciseIndex: 2, setIndex: 0),
            .setTargetChanged(exerciseIndex: 2, setID: Self.set(2, 0), weight: nil, reps: Reps(clamping: 7))
        ])
        #expect(plan.selection == WorkoutSelection(exerciseIndex: 2, setID: Self.set(2, 0)))
    }

    @Test("A logged row has no steppers: a step that names one does nothing")
    func step_onALoggedRow_comesToNothing() {
        let state = Self.logged([0], of: 0)
        #expect(Self.plan(.stepWeight(exerciseIndex: 0, setID: Self.set(0, 0), .increment), in: state).events == [])
        #expect(Self.plan(.stepReps(exerciseIndex: 0, setID: Self.set(0, 0), .increment), in: state).events == [])
    }
}
