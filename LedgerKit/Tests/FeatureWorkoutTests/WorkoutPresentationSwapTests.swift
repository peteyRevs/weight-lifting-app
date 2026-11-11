@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8b, criteria 13 to 16, 23 and 24: the swap button's rule and the swap sheet's model, word for word.
/// The presentation is pure: the sheet's state, the workout and the locale are arguments. The workout is the
/// spec's Upper A (`Fixtures.seedSession()`): Barbell Bench Press 5 × 5 @ 200 lb from the program's slot.
@Suite("WorkoutPresentation · the swap", .tags(.feature))
struct WorkoutPresentationSwapTests {
    static func sheet(
        _ alternatives: Loadable<[SwapChoice]>,
        in state: WorkoutState,
        alsoUpdateProgram: Bool = false
    ) -> SwapSheetModel {
        let bench = state.exercises[0]
        let swap = SwapState(
            exerciseIndex: 0,
            exerciseID: bench.exerciseID,
            alternatives: alternatives,
            alsoUpdateProgram: alsoUpdateProgram
        )
        return WorkoutPresentation.swapSheet(swap, in: state, locale: Fixtures.locale)
    }

    /// The bench press's alternatives on the shipped catalog, none done before: the store's own reading.
    static func benchChoices(in state: WorkoutState) throws -> [SwapChoice] {
        let catalog = try ExerciseCatalog.seed()
        let bench = state.exercises[0]
        let stored = try #require(catalog.first { $0.id == bench.exerciseID })
        let others = Set(state.exercises.map(\.exerciseID))
        return SwapAlternatives.ranked(for: stored, in: catalog, excluding: others).map { exercise in
            SwapChoice(
                replacing: bench.exerciseID,
                exerciseID: exercise.id,
                name: exercise.name,
                replacement: SwapAlternatives.replacement(of: bench, with: exercise, last: nil, units: state.units)
            )
        }
    }

    @Test("The rows read the alternatives' names and the loads their sets will take, in pounds, word for word")
    func rows_wordForWord_pounds() throws {
        let state = try Fixtures.seedSession()
        let model = try Self.sheet(.loaded(Self.benchChoices(in: state)), in: state)
        #expect(model.title == "Swap exercise")
        #expect(model.cancel == "Cancel")
        #expect(model.line == "Same movement pattern.")
        #expect(model.message == nil)
        #expect(model.rows.map { "\($0.name) | \($0.detail) | \($0.use)" } == [
            "Dumbbell Bench Press | Dumbbell · 15 lb | Use",
            "Smith Machine Bench Press | Machine · 40 lb | Use",
            "Weighted Dip | Bodyweight · 10 lb | Use",
            "Machine Chest Press | Machine · 40 lb | Use",
            "Barbell Floor Press | Barbell · 200 lb | Use",
            "Cable Chest Press | Cable · 30 lb | Use",
            "Decline Bench Press | Barbell · 200 lb | Use",
            // A load of zero is the equipment alone (Q7).
            "Decline Push-Up | Bodyweight | Use"
        ])
    }

    @Test("What a row shows is what its Use applies: the edit carries the same replacement and the toggle")
    func row_sendsWhatItShows() throws {
        let state = try Fixtures.seedSession()
        let choices = try Self.benchChoices(in: state)
        for isOn in [false, true] {
            let model = Self.sheet(.loaded(choices), in: state, alsoUpdateProgram: isOn)
            for (row, choice) in zip(model.rows, choices) {
                #expect(row.choose == .swap(exerciseIndex: 0, choice: choice, alsoUpdateProgram: isOn))
            }
        }
        let dumbbell = try #require(choices.first)
        #expect(dumbbell.replacement.load == .pounds(15))
        #expect(dumbbell.replacement.step == .pounds(2.5))
    }

    @Test("In kilograms a row reads its load in kilograms, as the Domain writes it")
    func rows_kilograms() throws {
        var state = try Fixtures.seedSession()
        state.units = .kg
        let choice = SwapChoice(
            replacing: state.exercises[0].exerciseID,
            exerciseID: ExerciseID(Fixtures.uuid(0x5B)),
            name: "Kettlebell Floor Press",
            replacement: SwappedExercise(
                equipment: .kettlebell,
                step: .kilograms(2),
                load: .kilograms(8),
                lastPerformance: nil
            )
        )
        let model = Self.sheet(.loaded([choice]), in: state)
        #expect(model.rows.map(\.detail) == ["Kettlebell · 8 kg"])
    }

    @Test("The swap's texts, word for word (F10 S8b)")
    func swapTexts_areWordForWord() {
        let plain = [
            WorkoutCopy.swapExercise, WorkoutCopy.cancel, WorkoutCopy.sameMovementPattern,
            WorkoutCopy.alsoUpdateProgram, WorkoutCopy.use, WorkoutCopy.couldNotLoadAlternatives,
            WorkoutCopy.noAlternatives
        ]
        #expect(plain == [
            "Swap exercise", "Cancel", "Same movement pattern.", "Also update program", "Use",
            "Couldn't load alternatives.", "No alternatives for this exercise."
        ])
        let locale = Fixtures.locale
        #expect(WorkoutCopy.equipmentAndLoad("Dumbbell", load: "15", units: .lb, locale: locale) == "Dumbbell · 15 lb")
        #expect(WorkoutCopy
            .equipmentAndLoad("Kettlebell", load: "8", units: .kg, locale: locale) == "Kettlebell · 8 kg")
    }

    @Test("Each kind of equipment has its own name")
    func equipment_names() {
        #expect(Equipment.allCases.map(WorkoutCopy.equipment) == [
            "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Band"
        ])
    }

    @Test("While the alternatives load: the line, and no row, no message and no switch")
    func loading_showsTheLineAlone() throws {
        let model = try Self.sheet(.loading, in: Fixtures.seedSession())
        #expect(model.line == "Same movement pattern.")
        #expect(model.rows.isEmpty && model.message == nil && model.toggle == nil)
    }

    @Test("A read that failed says so and offers nothing; nothing to offer says that, with no switch")
    func failedAndEmpty_lines() throws {
        let state = try Fixtures.seedSession()
        let failed = Self.sheet(.failed(SwapDoubleError()), in: state)
        #expect(failed.message == "Couldn't load alternatives.")
        #expect(failed.rows.isEmpty && failed.toggle == nil)
        let empty = Self.sheet(.loaded([]), in: state)
        #expect(empty.message == "No alternatives for this exercise.")
        #expect(empty.rows.isEmpty && empty.toggle == nil)
    }

    @Test("The switch opens as the store holds it, and is drawn only for an exercise from a program's slot")
    func toggle_onlyForAProgramSlot() throws {
        let state = try Fixtures.seedSession()
        let choices = try Self.benchChoices(in: state)
        let off = Self.sheet(.loaded(choices), in: state)
        #expect(off.toggle == SwapSheetModel.Toggle(label: "Also update program", isOn: false))
        #expect(Self.sheet(.loaded(choices), in: state, alsoUpdateProgram: true).toggle?.isOn == true)

        var adHoc = state
        adHoc.source = nil
        #expect(Self.sheet(.loaded(choices), in: adHoc).toggle == nil, "a workout from no program")
        var noSlot = state
        noSlot.exercises[0].slotID = nil
        #expect(Self.sheet(.loaded(choices), in: noSlot).toggle == nil, "an exercise from no slot")
    }

    @Test("Swap exercise is on the card while no set of the shown exercise is logged, and only then (Q2)")
    func button_onlyBeforeASetIsLogged() throws {
        var state = try Fixtures.seedSession()
        func card() -> ExerciseCardModel? {
            WorkoutPresentation.page(
                state,
                selection: nil,
                isBusy: false,
                WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)
            ).card
        }
        #expect(card()?.swap == "Swap exercise")
        state.exercises[0].sets[0].doneAt = Fixtures.now
        state.cursor = Cursor(exerciseIndex: 0, setIndex: 1)
        #expect(card()?.swap == nil, "after the first set is logged")
        state.exercises[0].sets[0].doneAt = nil
        #expect(card()?.swap == "Swap exercise", "un-logging it brings the button back")
        #expect(WorkoutPresentation.canSwap(state.exercises[1]))
    }
}

/// An error a double throws where a read fails.
struct SwapDoubleError: Error {}
