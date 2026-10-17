@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S5 criteria 3 to 5: the rules are the Domain's. The tester's own table of steps and floors
/// against what a tap comes to, and the page walked set by set through the real engine.
@MainActor
@Suite("Workout logging rules (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutRulesAdversarialLoggingTests {
    typealias Bench = PumpBench

    static let context = WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)

    /// The brief's table, written out: 5 lb barbell or kettlebell, 2.5 lb other; 2.5 kg barbell, 2 kg
    /// kettlebell, 1.25 kg other.
    nonisolated static func step(_ equipment: Equipment, _ units: Units) -> Decimal {
        switch (units, equipment) {
        case (.lb, .barbell), (.lb, .kettlebell): 5
        case (.lb, _): 2.5
        case (.kg, .barbell): 2.5
        case (.kg, .kettlebell): 2
        case (.kg, _): 1.25
        }
    }

    nonisolated static func weight(_ value: Decimal, _ units: Units) -> Weight {
        units == .lb ? .pounds(value) : .kilograms(value)
    }

    /// A workout of one exercise of `equipment` in `units`, as the Domain builds it: its step is the
    /// equipment's default, every row at `load`.
    static func workout(_ equipment: Equipment, _ units: Units, load: Decimal, reps: Int = 5) -> WorkoutState {
        let spec = EventBuilders.ExerciseSpec("Any", equipment, sets: 3, reps: reps, pounds: 0, restSeconds: 90)
        var state = EventBuilders.session([spec])
        state.units = units
        state.exercises[0].step = equipment.defaultStep(in: units)
        for index in state.exercises[0].sets.indices {
            state.exercises[0].sets[index].weight = weight(load, units)
        }
        return state
    }

    static func plan(_ edit: WorkoutEdit, in state: WorkoutState) -> WorkoutEditPlan {
        WorkoutEditPlan.make(edit, in: state, selection: nil, now: Fixtures.now) { SetID(EventBuilders.uuid(77)) }
    }

    @Test(
        "\"+\" and \"−\" move the weight by the step of the equipment and the unit, and the stepper names that step",
        arguments: Equipment.allCases,
        [Units.lb, .kg]
    )
    func stepWeight_isTheTablesStep(equipment: Equipment, units: Units) {
        let step = Self.step(equipment, units)
        let state = Self.workout(equipment, units, load: 40)
        let row = state.exercises[0].sets[0].id
        let card = WorkoutPresentation.card(of: 0, in: state, selection: nil, Self.context)
        #expect(card.steppers?.weightStep == "\(step) \(units == .lb ? "LB" : "KG")")
        for (direction, target) in [(SetRowSteppers.Direction.increment, 40 + step), (.decrement, 40 - step)] {
            let events = Self.plan(.stepWeight(exerciseIndex: 0, setID: row, direction), in: state).events
            #expect(events == [
                .setTargetChanged(exerciseIndex: 0, setID: row, weight: Self.weight(target, units), reps: nil)
            ])
        }
    }

    @Test("The weight never goes under 0 and the reps never under 1; at the floor a tap sends nothing")
    func floors_areHeld() async throws {
        let bench = try await Bench.make { $0 = Self.workout(.barbell, .lb, load: 7.5, reps: 2) }
        let row = bench.set(0, 0)
        for _ in 0 ..< 4 {
            bench.tap(
                .stepWeight(exerciseIndex: 0, setID: row, .decrement),
                .stepReps(exerciseIndex: 0, setID: row, .decrement)
            )
        }
        await bench.store.drain()
        let truth = try #require(await bench.settled())
        #expect(truth.exercises[0].sets[0].weight == .zero)
        #expect(truth.exercises[0].sets[0].reps == .one)
        // 7.5 → 2.5 → 0, and 2 → 1: three changes; the other five taps found the floor and sent nothing.
        #expect(await bench.session.applied.count == 3)
        #expect(bench.store.model.page?.card?.rows.first.map { "\($0.weight) × \($0.reps)" } == "0 × 1")
        bench.following.cancel()
    }

    @Test("The step is the exercise's own, as the workout was built with it, not the equipment's of today")
    func stepWeight_isTheWorkoutsOwnStep() {
        var state = Self.workout(.barbell, .lb, load: 100)
        state.exercises[0].step = .pounds(1)
        let row = state.exercises[0].sets[1].id
        let events = Self.plan(.stepWeight(exerciseIndex: 0, setID: row, .increment), in: state).events
        #expect(events.last == .setTargetChanged(exerciseIndex: 0, setID: row, weight: .pounds(101), reps: nil))
        #expect(
            events.first == .exerciseSelected(exerciseIndex: 0, setIndex: 1),
            "the second row was not the shown one"
        )
        #expect(events.count == 2)
    }

    /// Three working rows and a drop set, the second row logged.
    static func withADropSet() -> WorkoutState {
        var state = workout(.dumbbell, .kg, load: 20, reps: 12)
        let exercise = state.exercises[0]
        state.exercises[0].sets.append(LoggedSet(
            id: .derived(from: exercise.id, index: 3), weight: .kilograms(17.5), reps: Reps(clamping: 14), kind: .drop
        ))
        state.exercises[0].sets[1].doneAt = Fixtures.now
        return state
    }

    @Test("\"+ Add set\" after a drop set appends a copy of the drop set's row that is no drop set, numbered on")
    func addSet_afterADropSet() async throws {
        let bench = try await Bench.make { $0 = Self.withADropSet() }
        bench.tap(.addSet(exerciseIndex: 0), .addSet(exerciseIndex: 0))
        await bench.store.drain()
        let sets = try #require(await bench.settled()).exercises[0].sets
        #expect(sets.map(\.kind) == [.working, .working, .working, .drop, .added, .added])
        #expect(sets.suffix(2).map(\.weight) == [.kilograms(17.5), .kilograms(17.5)])
        #expect(sets.suffix(2).map(\.reps.value) == [14, 14])
        #expect(sets.suffix(2).allSatisfy { !$0.isDone })
        let card = try #require(bench.store.model.page?.card)
        #expect(card.rows.map(\.label) == ["1", "2", "3", "D", "4", "5"])
        #expect(card.rows.map(\.checkLabel) == [
            "Log set 1", "Undo set 2", "Log set 3", "Log drop set", "Log set 4", "Log set 5"
        ])
        #expect(bench.store.model.header?.segments.first?.length == 6)
        bench.following.cancel()
    }

    @Test("\"Repeat\" writes the last workout's weight and reps on every row, the drop set and the logged row too")
    func repeatLast_writesEveryRow() async throws {
        let bench = try await Bench.make {
            $0 = Self.withADropSet()
            $0.exercises[0].lastPerformance = LastPerformance(
                date: Fixtures.now.addingTimeInterval(-86400), sets: 3, reps: 9, load: .kilograms(18.75)
            )
        }
        #expect(bench.store.model.page?.card?.repeatLast == "Repeat")
        bench.tap(.repeatLast(exerciseIndex: 0))
        await bench.store.drain()
        let sets = try #require(await bench.settled()).exercises[0].sets
        #expect(sets.map(\.weight) == Array(repeating: .kilograms(18.75), count: 4))
        #expect(sets.map(\.reps.value) == [9, 9, 9, 9])
        #expect(sets.map(\.isDone) == [false, true, false, false])
        #expect(bench.store.model.page?.card?.rows.map(\.weight) == ["18.75", "18.75", "18.75", "18.75"])
        bench.following.cancel()
    }

    @Test("Without a last workout there is no \"Repeat\", and a tap that names it sends nothing")
    func repeatLast_withoutHistory() async throws {
        let bench = try await Bench.make { $0 = Self.withADropSet() }
        #expect(bench.store.model.page?.card?.repeatLast == nil)
        #expect(bench.store.model.page?.card?.last == "No history yet")
        bench.tap(.repeatLast(exerciseIndex: 0))
        await bench.store.drain()
        #expect(await bench.session.applied.isEmpty)
        bench.following.cancel()
    }
}
