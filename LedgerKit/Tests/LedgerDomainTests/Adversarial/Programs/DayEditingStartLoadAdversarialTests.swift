import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 7's start load: "the next multiple of the slot's step, or of the equipment's default step
/// in the lifter's unit, and never below zero", and exact decimals. The expected weight is worked in whole
/// numbers of 10⁻⁷ g by `EditAdv.referenceStep`, so a value such as 52.49999 cannot pass as 52.5.
@Suite("DayEditing start load (adversarial)", .tags(.domain))
struct DayEditingStartLoadAdversarialTests {
    /// The steps the two units use, in hundredths of the unit: 5, 2.5, 1.25 and the kettlebell's 2.
    static let steps = [500, 250, 125, 200]
    static let directions: [StepDirection] = [.upward, .downward]

    /// A bench slot with this load and step of its own, both in 10⁻⁷ g (`nil`: none of its own).
    static func slot(load: Int?, step: Int?, _ exercise: Exercise = Fixtures.bench) throws -> Slot {
        var slot = try Fixtures.slot(exercise, id: 1)
        slot.startLoad = load.map(EditAdv.weight(fine:))
        slot.step = step.map(EditAdv.weight(fine:))
        return slot
    }

    /// Every quarter of a unit from 0 to 400, stepped both ways by each step, the load in `loadUnits` and
    /// the step in `stepUnits`.
    static func sweep(loadUnits: Units, stepUnits: Units) throws -> Tally {
        var tally = Tally()
        var subject = try Self.slot(load: 0, step: 1)
        for stepHundredths in steps {
            let step = EditAdv.fine(hundredths: stepHundredths, stepUnits)
            subject.step = EditAdv.weight(fine: step)
            for quarter in 0 ... 1600 {
                let load = EditAdv.fine(hundredths: 25 * quarter, loadUnits)
                subject.startLoad = EditAdv.weight(fine: load)
                for direction in directions {
                    let expected = EditAdv.weight(fine: EditAdv.referenceStep(load: load, step: step, direction))
                    let field = DayEditing.stepped(
                        .startLoad,
                        direction,
                        of: subject,
                        exercise: Fixtures.bench,
                        units: .lb
                    )
                    let note = "\(25 * quarter)/100 \(loadUnits) \(direction) by \(stepHundredths)/100 \(stepUnits)"
                    tally.check(field == .startLoad(expected), "\(note): expected \(expected.grams) g, got \(field)")
                }
            }
        }
        return tally
    }
}

// MARK: - The next multiple, exactly

extension DayEditingStartLoadAdversarialTests {
    @Test(
        "Every quarter pound and quarter kilogram from 0 to 400 steps to the exact next multiple of a step in its unit."
    )
    func stepped_loadAndStepInOneUnit_isTheExactNextMultiple() throws {
        for units in Units.allCases {
            let tally = try Self.sweep(loadUnits: units, stepUnits: units)
            #expect(tally.passed, "\(units): \(tally.summary)")
            #expect(tally.cases == 4 * 1601 * 2)
        }
    }

    @Test("A load in one unit steps to the exact multiple of a step in the other unit, above or below it.")
    func stepped_loadInTheOtherUnit_goesToAMultipleOfTheStep() throws {
        let poundsByKilograms = try Self.sweep(loadUnits: .lb, stepUnits: .kg)
        #expect(poundsByKilograms.passed, "lb by kg: \(poundsByKilograms.summary)")
        let kilogramsByPounds = try Self.sweep(loadUnits: .kg, stepUnits: .lb)
        #expect(kilogramsByPounds.passed, "kg by lb: \(kilogramsByPounds.summary)")
    }

    @Test("From zero, \"−\" stays at zero and \"+\" is one step; from below one step, \"−\" is zero.")
    func stepped_atAndNearZero_neverGoesBelowZero() throws {
        let step = EditAdv.fine(hundredths: 500, .lb)
        let zero = try Self.slot(load: 0, step: step)
        let down = DayEditing.stepped(.startLoad, .downward, of: zero, exercise: Fixtures.bench, units: .lb)
        #expect(down == .startLoad(.zero))
        let above = DayEditing.stepped(.startLoad, .upward, of: zero, exercise: Fixtures.bench, units: .lb)
        #expect(above == .startLoad(.pounds(5)))
        let small = try Self.slot(load: EditAdv.fine(hundredths: 200, .lb), step: step)
        let floor = DayEditing.stepped(.startLoad, .downward, of: small, exercise: Fixtures.bench, units: .lb)
        #expect(floor == .startLoad(.zero))
        let one = try Self.slot(load: step, step: step)
        let last = DayEditing.stepped(.startLoad, .downward, of: one, exercise: Fixtures.bench, units: .lb)
        #expect(last == .startLoad(.zero))
    }

    @Test("Forty presses of \"+\" by 2.5 lb from zero are exactly 100 lb, and forty of \"−\" are exactly zero again.")
    func pressed_manyTimes_staysExact() throws {
        var day = try DayTemplate(
            id: EditAdv.dayID(4000),
            name: "Upper A",
            tag: "UA",
            slots: [Self.slot(load: 0, step: EditAdv.fine(hundredths: 250, .lb))]
        )
        var seen: [Weight?] = []
        for direction in Array(repeating: StepDirection.upward, count: 40) + Array(repeating: .downward, count: 40) {
            let slot = try #require(day.slots.first)
            let field = DayEditing.stepped(.startLoad, direction, of: slot, exercise: Fixtures.bench, units: .kg)
            day = DayEditing.set(field, slot: slot.id, in: day)
            seen.append(day.slots.first?.startLoad)
        }
        #expect(seen[0] == .pounds(2.5))
        #expect(seen[20] == .pounds(52.5))
        #expect(seen[39] == .pounds(100))
        #expect(seen[39]?.grams == dec("45359.237"))
        #expect(seen[79] == .zero)
        #expect(seen[79]?.grams == 0)
    }
}

// MARK: - Which load and which step

extension DayEditingStartLoadAdversarialTests {
    @Test("With no step of its own a slot steps by its equipment's step in the lifter's unit, for every equipment.")
    func stepped_noStepOfItsOwn_usesTheEquipmentsStepInTheLiftersUnit() throws {
        var tally = Tally()
        for equipment in Equipment.allCases {
            let exercise = Adversarial.catalogExercise(900, equipment, loads: [.lb: .pounds(45), .kg: .kilograms(20)])
            for units in Units.allCases {
                let step = EditAdv.fine(hundredths: EditAdv.defaultStepHundredths(equipment, units), units)
                for hundredths in stride(from: 0, through: 12000, by: 50) {
                    let load = EditAdv.fine(hundredths: hundredths, units)
                    let slot = try Self.slot(load: load, step: nil, exercise)
                    for direction in Self.directions {
                        let expected = EditAdv.weight(fine: EditAdv.referenceStep(load: load, step: step, direction))
                        let field = DayEditing.stepped(
                            .startLoad,
                            direction,
                            of: slot,
                            exercise: exercise,
                            units: units
                        )
                        tally.check(
                            field == .startLoad(expected),
                            "\(equipment) \(units) \(hundredths)/100 \(direction): \(field)"
                        )
                    }
                }
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 7 * 2 * 241 * 2)
    }

    @Test("With no load of its own a slot steps from the exercise's start load in the lifter's unit.")
    func stepped_noLoadOfItsOwn_startsFromTheExercisesLoad() throws {
        let slot = try Self.slot(load: nil, step: nil, Fixtures.inclineDB)
        func stepped(_ direction: StepDirection, _ units: Units) -> SlotField {
            DayEditing.stepped(.startLoad, direction, of: slot, exercise: Fixtures.inclineDB, units: units)
        }
        #expect(stepped(.upward, .lb) == .startLoad(.pounds(52.5)))
        #expect(stepped(.downward, .lb) == .startLoad(.pounds(47.5)))
        #expect(stepped(.upward, .kg) == .startLoad(.kilograms(23.75)))
        #expect(stepped(.downward, .kg) == .startLoad(.kilograms(21.25)))
        let own = try Self.slot(load: nil, step: EditAdv.fine(hundredths: 500, .lb), Fixtures.inclineDB)
        let field = DayEditing.stepped(.startLoad, .upward, of: own, exercise: Fixtures.inclineDB, units: .kg)
        #expect(field == .startLoad(.pounds(50)), "22.5 kg is 49.6 lb: the next multiple of the slot's 5 lb is 50 lb")
    }

    @Test("A slot's own step wins over the equipment's: a barbell slot with a 1.25 lb step moves 1.25 lb.")
    func stepped_ownStep_winsOverTheEquipments() throws {
        let slot = try Self.slot(load: EditAdv.fine(hundredths: 18000, .lb), step: EditAdv.fine(hundredths: 125, .lb))
        let above = DayEditing.stepped(.startLoad, .upward, of: slot, exercise: Fixtures.bench, units: .lb)
        #expect(above == .startLoad(.pounds(181.25)))
        let below = DayEditing.stepped(.startLoad, .downward, of: slot, exercise: Fixtures.bench, units: .kg)
        #expect(below == .startLoad(.pounds(178.75)))
    }

    @Test("A start-load press writes the start load alone: the step, its absence and every other field stay.")
    func pressed_startLoad_changesTheStartLoadAlone() throws {
        for step in [nil, EditAdv.fine(hundredths: 250, .kg)] {
            let slot = try Self.slot(load: nil, step: step)
            let day = DayTemplate(id: EditAdv.dayID(4000), name: "Upper A", tag: "UA", slots: [slot])
            let field = DayEditing.stepped(.startLoad, .upward, of: slot, exercise: Fixtures.bench, units: .kg)
            var expected = slot
            expected.startLoad = .kilograms(82.5)
            let onlyTheLoad = DayEditing.set(field, slot: slot.id, in: day).slots.first == expected
            #expect(onlyTheLoad, "step of its own: \(step != nil)")
        }
    }

    @Test(
        "set stores a start load that is not below zero exactly as given, on no step, and holds one below zero at zero."
    )
    func setStartLoad_isStoredExactly_andNeverBelowZero() throws {
        let slot = try Self.slot(load: EditAdv.fine(hundredths: 18000, .lb), step: nil)
        let day = DayTemplate(id: EditAdv.dayID(4000), name: "Upper A", tag: "UA", slots: [slot])
        var tally = Tally()
        for hundredths in -300 ... 3000 {
            for units in Units.allCases {
                let weight = EditAdv.weight(fine: EditAdv.fine(hundredths: hundredths, units))
                var expected = slot
                expected.startLoad = hundredths < 0 ? .zero : weight
                let stored = DayEditing.set(.startLoad(weight), slot: slot.id, in: day).slots.first
                tally.check(stored == expected, "\(hundredths)/100 \(units) gave \(stored?.startLoad?.grams ?? -1) g")
            }
        }
        #expect(tally.passed, tally.summary)
        let tiny = Weight(grams: dec("-0.0000001"))
        #expect(DayEditing.set(.startLoad(tiny), slot: slot.id, in: day).slots.first?.startLoad == .zero)
    }
}
