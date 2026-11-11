import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S8b: the plan at its turn (criterion 19) and the words (criterion 29).
extension WorkoutSwapRankingAdversarialTests {
    // MARK: The plan at its turn (criterion 19)

    private static func choice(for state: WorkoutState, _ name: String) throws -> SwapChoice {
        let exercise = try SwapG2Catalog.named(name)
        return SwapChoice(
            replacing: state.exercises[0].exerciseID,
            exerciseID: exercise.id,
            name: exercise.name,
            replacement: SwapAlternatives.replacement(
                of: state.exercises[0], with: exercise, last: nil, units: state.units
            )
        )
    }

    private static func plan(_ edit: WorkoutEdit, _ state: WorkoutState) -> [WorkoutEvent] {
        WorkoutEditPlan.make(edit, in: state, selection: nil, now: Fixtures.now) {
            SetID(EventBuilders.uuid(0xBEEF))
        }.events
    }

    @Test("The plan: one event when fresh; none for a gone index, another exercise, or a done set")
    func plan_staleCases() throws {
        let state = try SwapG2Catalog.workout()
        let choice = try Self.choice(for: state, "Dumbbell Bench Press")
        let fresh = Self.plan(.swap(exerciseIndex: 0, choice: choice, alsoUpdateProgram: true), state)
        #expect(fresh == [.exerciseSwapped(
            exerciseIndex: 0, exerciseID: choice.exerciseID, name: choice.name, alsoUpdateProgram: true,
            replacement: choice.replacement
        )])
        for index in [-1, 5, Int.max, Int.min] {
            #expect(Self.plan(.swap(exerciseIndex: index, choice: choice, alsoUpdateProgram: false), state).isEmpty)
        }
        // The choice was made for exercise 0; asked for exercise 1, it is another exercise.
        #expect(Self.plan(.swap(exerciseIndex: 1, choice: choice, alsoUpdateProgram: false), state).isEmpty)
        var logged = state
        logged.exercises[0].sets[4].doneAt = Fixtures.now
        #expect(Self.plan(.swap(exerciseIndex: 0, choice: choice, alsoUpdateProgram: false), logged).isEmpty)
    }

    @Test("FAILING (F10-S8b-G2-1): the plan swaps in an exercise the workout already holds elsewhere")
    func failing_plan_refusesAnExerciseAlreadyInTheWorkout() throws {
        var state = try SwapG2Catalog.workout()
        let dumbbell = try SwapG2Catalog.named("Dumbbell Bench Press")
        let choice = try Self.choice(for: state, dumbbell.name)
        state.exercises[3].exerciseID = dumbbell.id
        state.exercises[3].name = dumbbell.name
        let events = Self.plan(.swap(exerciseIndex: 0, choice: choice, alsoUpdateProgram: false), state)
        #expect(events.isEmpty, "Q9: the same exercise would stand at places 0 and 3")
    }

    // MARK: Words (criterion 29)

    @Test("Every word of the swap is in the module's catalog, translated, and resolves to the contract's text")
    func words_inTheCatalog() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/FeatureWorkout/Resources/Localizable.xcstrings")
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let strings = try #require(json["strings"] as? [String: Any])
        let keys = [
            "Swap exercise", "Cancel", "Use", "Also update program", "Same movement pattern.",
            "%@ · %@ lb", "%@ · %@ kg", "Couldn't load alternatives.", "No alternatives for this exercise.",
            "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Band"
        ]
        for key in keys {
            let entry = strings[key] as? [String: Any]
            let english = ((entry?["localizations"] as? [String: Any])?["en"] as? [String: Any])?["stringUnit"]
                as? [String: Any]
            #expect(english?["state"] as? String == "translated", "\(key)")
            #expect(entry?["extractionState"] as? String != "stale", "\(key) is stale")
        }
        #expect(WorkoutCopy.swapExercise == "Swap exercise")
        #expect(WorkoutCopy.sameMovementPattern == "Same movement pattern.")
        #expect(WorkoutCopy.alsoUpdateProgram == "Also update program")
        #expect(WorkoutCopy.use == "Use")
        #expect(WorkoutCopy.couldNotLoadAlternatives == "Couldn't load alternatives.")
        #expect(WorkoutCopy.noAlternatives == "No alternatives for this exercise.")
        #expect(
            WorkoutCopy.equipmentAndLoad("Kettlebell", load: "8", units: .kg, locale: Fixtures.locale)
                == "Kettlebell · 8 kg"
        )
        #expect(Equipment.allCases.map(WorkoutCopy.equipment) == Equipment.allCases.map { Self.equipmentWords[$0] })
    }
}
