import Foundation
@testable import LedgerDomain
import Testing

/// Deload rounding, kilogram programs, start-load/step resolution and a seeded spec oracle.
@Suite("ProgressionRules deload and units (adversarial)", .tags(.domain))
struct ProgressionRulesDeloadAdversarialTests {
    static func fixedSlot(_ exercise: Exercise, start: Weight?, step: Weight? = nil, id: Int = 950) throws -> Slot {
        try Fixtures.slot(exercise, id: id, progression: .fixed, startLoad: start, step: step)
    }

    static func deloadLoad(_ slot: Slot, _ exercise: Exercise, units: Units = .lb) -> Weight {
        ProgressionRulesAdversarialTests.prescribe(slot, exercise, week: 0, deload: true, units: units).load
    }
}

extension ProgressionRulesDeloadAdversarialTests {
    @Test(
        "Deload × 0.85 ties round away from zero to the step (rule 12, decision #3).",
        arguments: [
            // 150 × 0.85 = 127.5 → 25.5 steps of 5 → 26 → 130.
            ("150", "5", "130"),
            // 50 × 0.85 = 42.5 → 8.5 steps of 5 → 9 → 45.
            ("50", "5", "45"),
            // 25 × 0.85 = 21.25 → 8.5 steps of 2.5 → 9 → 22.5.
            ("25", "2.5", "22.5"),
            // 12.5 × 0.85 = 10.625 → 8.5 steps of 1.25 → 9 → 11.25.
            ("12.5", "1.25", "11.25"),
            // 212.5 × 0.85 = 180.625 → 144.5 steps of 1.25 → 145 → 181.25 (seed 3587324).
            ("212.5", "1.25", "181.25"),
            // 112.5 × 0.85 = 95.625 → 76.5 steps of 1.25 → 77 → 96.25.
            ("112.5", "1.25", "96.25"),
            // 285 × 0.85 = 242.25 → 48.45 → 48 → 240 (criterion 4's value, not a tie).
            ("285", "5", "240"),
            // 5 × 0.85 = 4.25 → 0.85 → 1 → 5.
            ("5", "5", "5")
        ]
    )
    func deload_poundTies_roundAwayFromZero(start: String, step: String, expected: String) throws {
        let slot = try Self.fixedSlot(Fixtures.backSquat, start: pounds(start), step: pounds(step))
        #expect(Self.deloadLoad(slot, Fixtures.backSquat) == pounds(expected))
    }

    @Test(
        "Kilogram deloads round to kilogram steps exactly (decision #9).",
        arguments: [("25", "2.5", 22500), ("110", "2.5", 92500), ("100", "2.5", 85000), ("22.5", "1.25", 18750)]
    )
    func deload_kilograms_roundToKiloStep(start: String, step: String, grams: Int) throws {
        // 25 × 0.85 = 21.25 = 8.5 × 2.5 → 22.5; 110 → 93.5 → 92.5; 22.5 → 19.125 → 15.3 × 1.25 → 18.75.
        let slot = try Self.fixedSlot(Fixtures.backSquat, start: kilos(start), step: kilos(step))
        #expect(Self.deloadLoad(slot, Fixtures.backSquat, units: .kg).grams == Decimal(grams))
    }

    @Test("A double-progression deload keeps the week's reps and cuts load, sets and RPE.")
    func deload_double_keepsReps() throws {
        // adv 5, span 3 → 52.5 × 12; 52.5 × 0.85 = 44.625 → 17.85 steps → 18 → 45.
        let slot = try ProgressionRulesAdversarialTests.incline()
        let prescription = ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.inclineDB, week: 5, deload: true)
        #expect(prescription.reps == 12)
        #expect(prescription.load == pounds("45"))
        #expect(prescription.sets == 2)
        #expect(try prescription.rpe == (Fixtures.rpe(6)))
    }

    @Test("A deload week still counts as advancement for the week after it (spec §7.2 adv).")
    func deload_weekAfter_hasAdvanced() throws {
        let slot = try ProgressionRulesAdversarialTests.squat()
        #expect(ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.backSquat, week: 8).load == pounds("290"))
    }

    @Test("The held flag survives into a deload week.")
    func deload_heldFlag_isKept() throws {
        // misses {6}: adv 6 → 280; 280 × 0.85 = 238 → 47.6 → 48 → 240.
        let slot = try ProgressionRulesAdversarialTests.squat(misses: [6])
        let prescription = ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.backSquat, week: 7, deload: true)
        #expect(prescription.isHeld)
        #expect(prescription.load == pounds("240"))
    }

    @Test("A zero start load deloads to zero.")
    func deload_zeroLoad_staysZero() throws {
        let slot = try Self.fixedSlot(Fixtures.backSquat, start: .zero)
        #expect(Self.deloadLoad(slot, Fixtures.backSquat) == .zero)
    }

    @Test("Kilogram programs use the kilogram start load and kilogram default steps (decision #9).")
    func kilograms_defaultsAndSteps() throws {
        let bench = try Fixtures.slot(Fixtures.bench, id: 951, sets: 5, reps: 5)
        let week3 = ProgressionRulesAdversarialTests.prescribe(bench, Fixtures.bench, week: 3, units: .kg)
        #expect(week3.load.grams == 87500)
        #expect(week3.step.grams == 2500)
        let incline = try Fixtures.slot(Fixtures.inclineDB, id: 952, reps: 10, repsHi: 12, progression: .double)
        let week4 = ProgressionRulesAdversarialTests.prescribe(incline, Fixtures.inclineDB, week: 4, units: .kg)
        #expect(week4.load.grams == 23750)
        #expect(week4.reps == 11)
        #expect(week4.step.grams == 1250)
    }

    @Test("Slot start load and step override the catalog and equipment defaults.")
    func overrides_winOverDefaults() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 953, startLoad: pounds("135"), step: pounds("2.5"))
        let prescription = ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.bench, week: 4)
        #expect(prescription.load == pounds("145"))
        #expect(prescription.step == pounds("2.5"))
        #expect(try prescription.rest == (Fixtures.rest(90)))
        #expect(prescription.progression == .linear)
    }

    @Test("A missing unit's start load converts and rounds to that unit's step; none at all is zero.")
    func startLoad_fallbacks() throws {
        // 185 lb = 83.915 kg → 33.566 steps of 2.5 → 85 kg; 80 kg = 176.37 lb → 35.27 steps of 5 → 175 lb.
        let poundsOnly = Adversarial.catalogExercise(960, .barbell, loads: [.lb: pounds("185")])
        let kilosOnly = Adversarial.catalogExercise(961, .barbell, loads: [.kg: kilos("80")])
        let none = Adversarial.catalogExercise(962, .dumbbell, loads: [:])
        #expect(poundsOnly.startLoad(in: .kg) == kilos("85"))
        #expect(kilosOnly.startLoad(in: .lb) == pounds("175"))
        #expect(none.startLoad(in: .lb) == .zero)
        let slot = try Fixtures.slot(poundsOnly, id: 954)
        #expect(ProgressionRulesAdversarialTests.prescribe(slot, poundsOnly, week: 1, units: .kg).load == kilos("87.5"))
    }

    @Test("A 52-week linear block lands exactly on the pound literal (user story 2).")
    func linear_longBlock_isExact() throws {
        let slot = try ProgressionRulesAdversarialTests.squat()
        let prescription = ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.backSquat, week: 52)
        #expect(prescription.load == pounds("510"))
        #expect(prescription.load.formatted(in: .lb) == "510")
    }

    @Test("targetLine reads '{sets} × {reps} @ {load} {unit} · RPE {rpe}' (rule 14).")
    func targetLine_format() throws {
        let slot = try ProgressionRulesAdversarialTests.squat(rpe: dec("8.5"))
        let prescription = ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.backSquat, week: 0)
        #expect(prescription.targetLine(units: .lb) == "5 × 5 @ 250 lb · RPE 8.5")
        let kilo = try Fixtures.slot(Fixtures.inclineDB, id: 955, reps: 10, repsHi: 12, progression: .double)
        let kiloLine = ProgressionRulesAdversarialTests.prescribe(kilo, Fixtures.inclineDB, week: 0, units: .kg)
        #expect(kiloLine.targetLine(units: .kg) == "3 × 10 @ 22.5 kg · RPE 8")
    }
}
