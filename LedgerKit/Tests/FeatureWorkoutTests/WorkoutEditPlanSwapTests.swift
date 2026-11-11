@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8b, criteria 18 and 19: what "Use" comes to at its turn in the tap queue. One `exerciseSwapped` with the
/// choice's replacement and the toggle; nothing when the workout has moved past the choice.
@Suite("WorkoutEditPlan · the swap", .tags(.feature))
struct WorkoutEditPlanSwapTests {
    static let seed = EventBuilders.seedSession()

    /// Bench (exercise 0) swapped for a dumbbell press at 15 lb, as the sheet would offer it.
    static let choice = SwapChoice(
        replacing: seed.exercises[0].exerciseID,
        exerciseID: ExerciseID(EventBuilders.uuid(0xDB)),
        name: "Dumbbell Bench Press",
        replacement: SwappedExercise(equipment: .dumbbell, step: .pounds(2.5), load: .pounds(15), lastPerformance: nil)
    )

    static func plan(
        _ state: WorkoutState = seed,
        at index: Int = 0,
        alsoUpdateProgram: Bool = false,
        selection: WorkoutSelection? = nil
    ) -> WorkoutEditPlan {
        WorkoutEditPlan.make(
            .swap(exerciseIndex: index, choice: choice, alsoUpdateProgram: alsoUpdateProgram),
            in: state,
            selection: selection,
            now: Fixtures.now
        ) { SetID(EventBuilders.uuid(0xADD)) }
    }

    @Test("Use is one exerciseSwapped carrying the choice, its replacement and the toggle; the selection stays")
    func use_isOneEvent() {
        let selection = WorkoutSelection(exerciseIndex: 0, setID: EventBuilders.setID(0, 2))
        for isOn in [false, true] {
            let plan = Self.plan(alsoUpdateProgram: isOn, selection: selection)
            #expect(plan.events == [.exerciseSwapped(
                exerciseIndex: 0,
                exerciseID: Self.choice.exerciseID,
                name: "Dumbbell Bench Press",
                alsoUpdateProgram: isOn,
                replacement: Self.choice.replacement
            )])
            #expect(plan.selection == selection)
        }
    }

    @Test("A choice for an exercise the place no longer holds comes to nothing")
    func staleExercise_comesToNothing() {
        var moved = Self.seed
        moved.exercises[0].exerciseID = ExerciseID(EventBuilders.uuid(0x1C))
        #expect(Self.plan(moved).events.isEmpty)
        #expect(Self.plan(at: 1).events.isEmpty, "another place holds another exercise")
    }

    @Test("A choice for an exercise that now has a set logged comes to nothing (Q2)")
    func loggedSet_comesToNothing() {
        var logged = Self.seed
        logged.exercises[0].sets[3].doneAt = Fixtures.now
        #expect(Self.plan(logged).events.isEmpty)
    }

    @Test("A choice the workout now holds at another place comes to nothing (Q9, F10-S8b-G2-1)")
    func exerciseHeldElsewhere_comesToNothing() {
        var taken = Self.seed
        taken.exercises[3].exerciseID = Self.choice.exerciseID
        #expect(Self.plan(taken).events.isEmpty)
        #expect(!Self.plan().events.isEmpty, "held at no other place, it is swapped in")
    }

    @Test("A choice for a place the workout no longer has comes to nothing")
    func goneIndex_comesToNothing() {
        #expect(Self.plan(at: 5).events.isEmpty)
        #expect(Self.plan(at: -1).events.isEmpty)
    }
}
