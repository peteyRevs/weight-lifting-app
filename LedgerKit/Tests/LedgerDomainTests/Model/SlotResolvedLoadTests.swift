import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S6, criterion 8: the start load and the step a slot resolves to in a unit (spec §7.2; rule 1,
/// decisions #9 and #22). The slot's own value wins; without one the exercise and its equipment decide.
@Suite("Slot · resolved start load and step", .tags(.domain))
struct SlotResolvedLoadTests {
    static let kettlebell = Fixtures.exercise(30, "Kettlebell Swing", .kettlebell, pounds: 25, kilograms: 12)

    @Test("A slot with no start load of its own starts from its exercise's, in the unit asked for")
    func resolvedStartLoad_none_isTheExercises() throws {
        let slot = try Fixtures.slot(Fixtures.inclineDB, id: 1)
        #expect(slot.resolvedStartLoad(exercise: Fixtures.inclineDB, units: .lb) == .pounds(50))
        #expect(slot.resolvedStartLoad(exercise: Fixtures.inclineDB, units: .kg) == .kilograms(22.5))
    }

    @Test("A slot's own start load wins in either unit, zero included, and is not converted or rounded")
    func resolvedStartLoad_own_wins() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, startLoad: .pounds(182.5))
        #expect(slot.resolvedStartLoad(exercise: Fixtures.bench, units: .lb) == .pounds(182.5))
        #expect(slot.resolvedStartLoad(exercise: Fixtures.bench, units: .kg) == .pounds(182.5))
        let empty = try Fixtures.slot(Fixtures.bench, id: 2, startLoad: .zero)
        #expect(empty.resolvedStartLoad(exercise: Fixtures.bench, units: .lb) == .zero)
    }

    @Test("An exercise with a start load in one unit only gives it rounded to the other unit's step")
    func resolvedStartLoad_oneUnitOnly_isTheExercisesConversion() throws {
        var exercise = Fixtures.bench
        exercise.defaultStartLoad = [.lb: .pounds(180)]
        let slot = try Fixtures.slot(exercise, id: 1)
        #expect(slot.resolvedStartLoad(exercise: exercise, units: .kg) == exercise.startLoad(in: .kg))
        #expect(slot.resolvedStartLoad(exercise: exercise, units: .kg) == .kilograms(82.5))
    }

    @Test(
        "A slot with no step of its own moves by its equipment's default step in the unit",
        arguments: [
            (Fixtures.bench, Units.lb, Weight.pounds(5)),
            (Fixtures.bench, Units.kg, Weight.kilograms(2.5)),
            (Fixtures.inclineDB, Units.lb, Weight.pounds(2.5)),
            (Fixtures.inclineDB, Units.kg, Weight.kilograms(1.25)),
            (kettlebell, Units.lb, Weight.pounds(5)),
            (kettlebell, Units.kg, Weight.kilograms(2))
        ]
    )
    func resolvedStep_none_isTheEquipmentsDefault(exercise: Exercise, units: Units, expected: Weight) throws {
        let slot = try Fixtures.slot(exercise, id: 1)
        #expect(slot.resolvedStep(exercise: exercise, units: units) == expected)
    }

    @Test("A slot's own step wins in either unit")
    func resolvedStep_own_wins() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, step: .pounds(10))
        #expect(slot.resolvedStep(exercise: Fixtures.bench, units: .lb) == .pounds(10))
        #expect(slot.resolvedStep(exercise: Fixtures.bench, units: .kg) == .pounds(10))
    }

    @Test("A prescription and the start load's stepper read the pair through these two functions")
    func resolved_areWhatThePrescriptionAndTheStepperUse() throws {
        for units in Units.allCases {
            let slot = try Fixtures.slot(Self.kettlebell, id: 1)
            let week = Week(id: WeekID(Fixtures.uuid(200)), index: 0)
            let first = ProgressionRules.prescribe(
                week: week,
                weekIndex: 0,
                slot: slot,
                exercise: Self.kettlebell,
                units: units
            )
            let start = slot.resolvedStartLoad(exercise: Self.kettlebell, units: units)
            let step = slot.resolvedStep(exercise: Self.kettlebell, units: units)
            #expect(first.load == start)
            #expect(first.step == step)
            let raised = DayEditing.stepped(.startLoad, .upward, of: slot, exercise: Self.kettlebell, units: units)
            #expect(raised == .startLoad(start + step))
        }
    }
}
