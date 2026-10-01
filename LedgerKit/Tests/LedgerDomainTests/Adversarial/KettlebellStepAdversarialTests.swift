import Foundation
@testable import LedgerDomain
import Testing

/// Decision #22 (kettlebells step 5 lb / 2 kg) through the F02 rules that read the step, on the
/// catalog's own kettlebell entries.
@Suite("Kettlebell step (adversarial)", .tags(.domain))
struct KettlebellStepAdversarialTests {
    static func swing() throws -> Exercise {
        try CatalogUnderTest.named("Kettlebell Swing", in: CatalogUnderTest.exercises())
    }

    /// The nearest multiple of `step`, ties away from zero (decision #3), in exact decimals.
    static func nearest(_ value: Decimal, step: Decimal) -> Decimal {
        decimalRounded(value / step, scale: 0, .plain) * step
    }

    static func prescribe(
        _ exercise: Exercise,
        week: Int,
        deload: Bool = false,
        units: Units,
        progression: Progression = .linear,
        startLoad: Weight? = nil
    ) throws -> Prescription {
        let slot = try Fixtures.slot(exercise, id: 700, reps: 8, progression: progression, startLoad: startLoad)
        return ProgressionRules.prescribe(
            week: Fixtures.week(week, deload: deload),
            weekIndex: week,
            slot: slot,
            exercise: exercise,
            units: units
        )
    }
}

extension KettlebellStepAdversarialTests {
    @Test("Only kettlebells changed step: every (equipment, unit) pair matches decisions #9 and #22.")
    func defaultStep_onlyKettlebellChanged() {
        for equipment in Equipment.allCases {
            for units in Units.allCases {
                let expected: Weight = units == .lb
                    ? .pounds(StepOracle.step(equipment, units))
                    : .kilograms(StepOracle.step(equipment, units))
                #expect(equipment.defaultStep(in: units) == expected, "\(equipment) \(units)")
            }
        }
    }

    @Test("Linear progression from the catalog's swing adds one bell size a week: 12, 14 … kg and 25, 30 … lb.")
    func linear_addsOneBellSizePerWeek() throws {
        let swing = try Self.swing()
        for week in 0 ..< 7 {
            let kg = try Self.prescribe(swing, week: week, units: .kg)
            let lb = try Self.prescribe(swing, week: week, units: .lb)
            #expect(kg.load == .kilograms(12 + 2 * Decimal(week)))
            #expect(lb.load == .pounds(25 + 5 * Decimal(week)))
            #expect(kg.step == .kilograms(2))
            #expect(lb.step == .pounds(5))
        }
        // Double progression: 8 → 10 reps over three weeks, then one bell up.
        let double = try Self.prescribe(swing, week: 3, units: .kg, progression: .double)
        #expect(double.load == .kilograms(14))
        #expect(double.reps == 8)
    }

    @Test("A deload rounds × 0.85 to the nearest 2 kg / 5 lb, ties up (decision #3), for every start and week.")
    func deload_roundsToABell() throws {
        let swing = try Self.swing()
        for start in stride(from: 4, through: 32, by: 2) {
            for week in 0 ..< 8 {
                let prescription = try Self.prescribe(
                    swing, week: week, deload: true, units: .kg, startLoad: .kilograms(Decimal(start))
                )
                let raw = (Decimal(start) + 2 * Decimal(week)) * dec("0.85")
                #expect(prescription.load == .kilograms(Self.nearest(raw, step: 2)), "\(start) kg, week \(week)")
                #expect(StepOracle.isMultiple(prescription.load.kilograms, of: 2))
            }
        }
        // 20 kg × 0.85 = 17 kg, halfway between bells: the tie goes to 18 kg (rounded away from zero).
        let tie = try Self.prescribe(swing, week: 0, deload: true, units: .kg, startLoad: .kilograms(20))
        #expect(tie.load == .kilograms(18))
        let pounds = try Self.prescribe(swing, week: 7, deload: true, units: .lb)
        #expect(pounds.load == .pounds(50)) // (25 + 35) × 0.85 = 51 → 50
    }

    @Test("A kettlebell drop set in a built session lands on a bell, and the session keeps the 2 kg step.")
    func session_dropSetOnABell() throws {
        let swing = try Self.swing()
        let day = try DayTemplate(
            id: DayTemplateID(Fixtures.uuid(710)),
            name: "Bells",
            tag: "KB",
            slots: [Fixtures.slot(swing, id: 711, sets: 2, reps: 10, dropSets: 1)]
        )
        var settings = Settings.default
        settings.units = .kg
        let workout = try SessionBuilder.build(
            program: Fixtures.program(days: [day]),
            weekIndex: 1,
            day: day,
            exercises: [swing.id: swing],
            history: [:],
            settings: settings,
            id: Fixtures.workoutID,
            device: Fixtures.deviceID,
            now: Fixtures.now
        )
        let exercise = try #require(workout.exercises.first)
        #expect(exercise.step == .kilograms(2))
        #expect(exercise.sets.map(\.weight) == [.kilograms(14), .kilograms(14), .kilograms(12)]) // 11.9 → 12
    }

    @Test(
        "A missing unit converts to the nearest 5 lb / 2 kg: 8 kg → 20 lb, 16 kg → 35 lb, 15 lb → 6 kg, 35 lb → 16 kg."
    )
    func conversion_landsOnABell() throws {
        var bell = try Self.swing()
        for kg in stride(from: 4, through: 48, by: 2) {
            bell.defaultStartLoad = [.kg: .kilograms(Decimal(kg))]
            let expected = Self.nearest(Weight.kilograms(Decimal(kg)).pounds, step: 5)
            #expect(bell.startLoad(in: .lb) == .pounds(expected), "\(kg) kg")
        }
        for lb in stride(from: 5, through: 100, by: 5) {
            bell.defaultStartLoad = [.lb: .pounds(Decimal(lb))]
            let expected = Self.nearest(Weight.pounds(Decimal(lb)).kilograms, step: 2)
            #expect(bell.startLoad(in: .kg) == .kilograms(expected), "\(lb) lb")
        }
        bell.defaultStartLoad = [.kg: .kilograms(8)]
        #expect(bell.startLoad(in: .lb) == .pounds(20))
        bell.defaultStartLoad = [.lb: .pounds(15)]
        #expect(bell.startLoad(in: .kg) == .kilograms(6))
    }

    @Test("Each catalog kettlebell's lb and kg loads are the same bell within one step of each other.")
    func catalogBells_unitsAgree() throws {
        for exercise in try CatalogUnderTest.exercises() where exercise.equipment == .kettlebell {
            let lb = try #require(exercise.defaultStartLoad[.lb])
            let kg = try #require(exercise.defaultStartLoad[.kg])
            let converted = Self.nearest(lb.kilograms, step: 2)
            #expect(abs(converted - kg.kilograms) <= 2, "\(exercise.name): \(lb.pounds) lb vs \(kg.kilograms) kg")
        }
    }

    @Test("PRs on a kettlebell: one bell up at the same reps is a weight and e1RM PR; the same bell is neither.")
    func personalRecords_kettlebell() throws {
        let swing = try Self.swing()
        let previous = try #require(OneRepMax.brzycki(weight: kilos("14"), reps: Fixtures.reps(5)))
        func records(_ kg: String) throws -> [PersonalRecord] {
            let rows = [Adversarial.row(1, weight: kilos(kg), reps: 5)]
            let workout = try Fixtures.workout([Adversarial.exercise(swing, rows: rows)])
            return try PersonalRecords.detect(
                workout: workout,
                bestE1RM: [swing.id: previous],
                bestWeightAtReps: [swing.id: [Fixtures.reps(5): kilos("14")]],
                now: Fixtures.now
            )
        }
        let oneBellUp = try records("16")
        let five = try Fixtures.reps(5)
        #expect(oneBellUp.count == 2)
        #expect(oneBellUp.contains { $0.kind == .weightAtReps(kilos("16"), five) })
        #expect(try records("14").isEmpty)
    }
}
