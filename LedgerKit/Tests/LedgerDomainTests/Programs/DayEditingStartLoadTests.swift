import Foundation
@testable import LedgerDomain
import Testing

/// F11 slice S1, criterion 7: the start load's stepper (rules 1 and 6; decisions #9 and #22). The load goes
/// to the next multiple of the step on the side asked for, never below zero, in exact decimals.
@Suite("DayEditing · start load", .tags(.domain))
struct DayEditingStartLoadTests {
    struct Row: Sendable, CustomStringConvertible {
        let description: String
        var exercise = Fixtures.bench
        var units = Units.lb
        var startLoad: Weight?
        var step: Weight?
        let downward: Weight
        let upward: Weight

        static let kettlebell = Fixtures.exercise(30, "Kettlebell Swing", .kettlebell, pounds: 25, kilograms: 12)

        static let onTheSteps: [Row] = [
            Row(
                description: "barbell, lb: 180 from the exercise, step 5",
                downward: .pounds(175),
                upward: .pounds(185)
            ),
            Row(
                description: "barbell, kg: 80, step 2.5",
                units: .kg,
                downward: .kilograms(77.5),
                upward: .kilograms(82.5)
            ),
            Row(
                description: "dumbbell, lb: 50, step 2.5",
                exercise: Fixtures.inclineDB,
                downward: .pounds(47.5),
                upward: .pounds(52.5)
            ),
            Row(
                description: "dumbbell, kg: 22.5, step 1.25",
                exercise: Fixtures.inclineDB,
                units: .kg,
                downward: .kilograms(21.25),
                upward: .kilograms(23.75)
            ),
            Row(
                description: "kettlebell, lb: 25, step 5",
                exercise: kettlebell,
                downward: .pounds(20),
                upward: .pounds(30)
            ),
            Row(
                description: "kettlebell, kg: 12, step 2 (decision #22)",
                exercise: kettlebell,
                units: .kg,
                downward: .kilograms(10),
                upward: .kilograms(14)
            ),
            Row(
                description: "the slot's own load and step win: 100 by 10",
                startLoad: .pounds(100),
                step: .pounds(10),
                downward: .pounds(90),
                upward: .pounds(110)
            ),
            Row(description: "zero stays zero going down", startLoad: .zero, downward: .zero, upward: .pounds(5))
        ]

        static let offTheSteps: [Row] = [
            Row(
                description: "180 lb read in kilograms is 81.6: 80 and 82.5",
                units: .kg,
                startLoad: .pounds(180),
                downward: .kilograms(80),
                upward: .kilograms(82.5)
            ),
            Row(
                description: "181.3 lb: 180 and 185",
                startLoad: .pounds(dec("181.3")),
                downward: .pounds(180),
                upward: .pounds(185)
            ),
            Row(description: "2 lb: zero and 5", startLoad: .pounds(2), downward: .zero, upward: .pounds(5)),
            Row(
                description: "60 kg read in pounds is 132.3: 130 and 135",
                startLoad: .kilograms(60),
                downward: .pounds(130),
                upward: .pounds(135)
            ),
            Row(
                description: "a 12 kg bell on a 2.5 kg step: 10 and 12.5",
                exercise: kettlebell,
                units: .kg,
                step: .kilograms(2.5),
                downward: .kilograms(10),
                upward: .kilograms(12.5)
            )
        ]
    }

    private func custom(_ loads: [Units: Weight]) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(40)),
            name: "Custom Press",
            shortName: "CUSTOM",
            equipment: .dumbbell,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: loads,
            isCustom: true
        )
    }

    /// The start load one step down and one step up.
    private func loads(_ slot: Slot, _ exercise: Exercise, _ units: Units) -> [SlotField] {
        [StepDirection.downward, .upward].map { direction in
            DayEditing.stepped(.startLoad, direction, of: slot, exercise: exercise, units: units)
        }
    }
}

extension DayEditingStartLoadTests {
    @Test(
        "The start load moves by the slot's step, or the equipment's in the lifter's unit (rules 1 and 6)",
        arguments: Row.onTheSteps + Row.offTheSteps
    )
    func steppedStartLoad_goesToTheNextMultiple(row: Row) throws {
        let slot = try Fixtures.slot(row.exercise, id: 1, startLoad: row.startLoad, step: row.step)
        #expect(loads(slot, row.exercise, row.units) == [.startLoad(row.downward), .startLoad(row.upward)])
    }

    @Test("A start load off the unit's steps goes to the next multiple above or below, exactly")
    func steppedStartLoad_offTheSteps_goesToTheNextMultiple() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, startLoad: .pounds(180))
        #expect(slot.startLoad?.formatted(in: .kg) == "81.6")
        let stepped = loads(slot, Fixtures.bench, .kg)
        #expect(stepped == [.startLoad(Weight(grams: 80000)), .startLoad(Weight(grams: 82500))])
        let day = DayTemplate(id: DayTemplateID(Fixtures.uuid(500)), name: "Day", tag: "DY", slots: [slot])
        let stored = DayEditing.set(stepped[1], slot: slot.id, in: day).slots[0].startLoad
        #expect(stored?.formatted(in: .kg) == "82.5")
        #expect(stored?.grams == 82500)
    }

    @Test("Pound loads stay exact through many steps: 185 lb up six 2.5 lb steps is 200 lb to the gram")
    func steppedStartLoad_manySteps_staysExact() throws {
        var slot = try Fixtures.slot(Fixtures.inclineDB, id: 1, startLoad: .pounds(185))
        for _ in 1 ... 6 {
            guard case let .startLoad(next) = loads(slot, Fixtures.inclineDB, .lb)[1] else {
                Issue.record("stepped(.startLoad) gave another field")
                return
            }
            slot.startLoad = next
        }
        #expect(slot.startLoad == .pounds(200))
        #expect(slot.startLoad?.grams == dec("90718.474"))
    }

    @Test("An exercise with a load in one unit only steps from that load on the other unit's step")
    func steppedStartLoad_exerciseWithOneUnit_usesTheConvertedLoad() throws {
        let exercise = custom([.lb: .pounds(100)])
        let slot = try Fixtures.slot(exercise, id: 1)
        #expect(loads(slot, exercise, .kg) == [.startLoad(.kilograms(43.75)), .startLoad(.kilograms(46.25))])
        let bare = custom([:])
        #expect(try loads(Fixtures.slot(bare, id: 2), bare, .kg) == [.startLoad(.zero), .startLoad(.kilograms(1.25))])
    }

    @Test("The start load never goes below zero, even from an exercise whose own load is below zero")
    func steppedStartLoad_neverBelowZero() throws {
        let exercise = custom([.lb: .pounds(-10), .kg: .kilograms(-5)])
        let slot = try Fixtures.slot(exercise, id: 1)
        #expect(loads(slot, exercise, .lb) == [.startLoad(.zero), .startLoad(.zero)])
        var outside = slot
        outside.startLoad = Weight(grams: .nan)
        outside.step = .zero
        #expect(loads(outside, exercise, .lb) == [.startLoad(.zero), .startLoad(.zero)], "no number, no step: zero")
        outside.startLoad = .pounds(50)
        #expect(
            loads(outside, exercise, .lb) == [.startLoad(.pounds(50)), .startLoad(.pounds(50))],
            "a zero step moves nothing"
        )
    }
}
