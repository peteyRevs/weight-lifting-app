import Foundation
@testable import LedgerDomain
import Testing

/// Spec §6.4 seed slots prescribed at chosen weeks; expected values worked by hand from spec §7.2.
enum ProgressionFixtures {
    struct Row: Sendable, CustomStringConvertible {
        let description: String
        let exercise: Exercise
        var progression: Progression = .linear
        var sets = 3
        var reps = 8
        var repsHi: Int?
        var rpe: Decimal = 8
        var step: Weight?
        var misses: Set<Int> = []
        let week: Int
        var deload = false
        let load: Weight
        let expectedReps: Int
        var expectedSets: Int?
        var expectedRPE: Decimal?
        var held = false
    }

    static let rows: [Row] = [
        Row(
            description: "Bench linear W1: start 180",
            exercise: Fixtures.bench,
            sets: 5,
            reps: 5,
            week: 0,
            load: .pounds(180),
            expectedReps: 5
        ),
        Row(
            description: "Bench linear W4: 180 + 3 × 5",
            exercise: Fixtures.bench,
            sets: 5,
            reps: 5,
            week: 3,
            load: .pounds(195),
            expectedReps: 5
        ),
        Row(
            description: "Incline double W5: 52.5 × 11",
            exercise: Fixtures.inclineDB,
            progression: .double,
            reps: 10,
            week: 4,
            load: .pounds(52.5),
            expectedReps: 11
        ),
        Row(
            description: "Pulldown double W7: 105 × 12",
            exercise: Fixtures.latPulldown,
            progression: .double,
            reps: 12,
            week: 6,
            load: .pounds(105),
            expectedReps: 12
        ),
        Row(
            description: "Lateral double W3: 12.5 × 17",
            exercise: Fixtures.lateralRaise,
            progression: .double,
            reps: 15,
            week: 2,
            load: .pounds(12.5),
            expectedReps: 17
        ),
        Row(
            description: "Row fixed W6: 65 × 12",
            exercise: Fixtures.chestSupportedRow,
            progression: .fixed,
            reps: 12,
            step: .pounds(2.5),
            week: 5,
            load: .pounds(65),
            expectedReps: 12
        ),
        Row(
            description: "Squat deload W8: 285 → 240",
            exercise: Fixtures.backSquat,
            sets: 5,
            reps: 5,
            week: 7,
            deload: true,
            load: .pounds(240),
            expectedReps: 5,
            expectedSets: 4,
            expectedRPE: 6
        ),
        Row(
            description: "Deadlift-style deload tie: 350 × 0.85 = 297.5 → 300",
            exercise: Fixtures.backSquat,
            sets: 4,
            reps: 4,
            step: .pounds(5),
            misses: [],
            week: 20,
            deload: true,
            load: .pounds(300),
            expectedReps: 4,
            expectedSets: 3,
            expectedRPE: 6
        ),
        Row(
            description: "Double deload W8: 105 × 13 → 90 × 13",
            exercise: Fixtures.latPulldown,
            progression: .double,
            reps: 12,
            rpe: 9,
            step: .pounds(2.5),
            week: 7,
            deload: true,
            load: .pounds(90),
            expectedReps: 13,
            expectedSets: 2,
            expectedRPE: 7
        ),
        Row(
            description: "Three straight misses hold the start load",
            exercise: Fixtures.bench,
            misses: [0, 1, 2],
            week: 3,
            load: .pounds(180),
            expectedReps: 8,
            held: true
        ),
        Row(
            description: "Step override 10 lb",
            exercise: Fixtures.bench,
            step: .pounds(10),
            week: 2,
            load: .pounds(200),
            expectedReps: 8
        ),
        Row(
            description: "Double span 2 (repsHi = reps + 1)",
            exercise: Fixtures.inclineDB,
            progression: .double,
            reps: 10,
            repsHi: 11,
            week: 3,
            load: .pounds(52.5),
            expectedReps: 11
        )
    ]
}

@Suite("ProgressionRules", .tags(.domain))
struct ProgressionRulesTests {
    private func prescribe(
        _ slot: Slot,
        _ exercise: Exercise,
        week: Int,
        deload: Bool = false,
        units: Units = .lb
    ) -> Prescription {
        ProgressionRules.prescribe(
            week: Fixtures.week(week, deload: deload), weekIndex: week, slot: slot, exercise: exercise, units: units
        )
    }

    @Test("Linear adds one step per completed prior week (rule 9)")
    func linear_advancesByStepPerCompletedWeek() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, sets: 5, reps: 5)
        let loads = (0 ..< 7).map { prescribe(slot, Fixtures.bench, week: $0).load }
        #expect(loads == [180, 185, 190, 195, 200, 205, 210].map(Weight.pounds))
        #expect(prescribe(slot, Fixtures.bench, week: 3).reps == 5)
    }

    @Test("A missed week does not advance, so the load holds (rule 9, criterion 5)")
    func linear_missedWeekHoldsLoad() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, misses: [1])
        let weekThree = prescribe(slot, Fixtures.bench, week: 3)
        // adv = |{0, 2}| = 2, so load = start + 2 · step.
        #expect(weekThree.load == Weight.pounds(180).advanced(bySteps: 2, of: .pounds(5)))
        #expect(weekThree.load == .pounds(190))
        #expect(!weekThree.isHeld)
        #expect(prescribe(slot, Fixtures.bench, week: 2).load == .pounds(185))
    }

    @Test("Double progression climbs reps, then raises the load and resets reps (rule 10, criterion 3)")
    func double_repsClimbThenLoadRisesAndRepsReset() throws {
        let slot = try Fixtures.slot(
            Fixtures.inclineDB, id: 2, reps: 10, repsHi: 12, progression: .double, step: .pounds(2.5)
        )
        let weeks = (0 ... 3).map { prescribe(slot, Fixtures.inclineDB, week: $0) }
        #expect(weeks.map(\.load) == [50, 50, 50, 52.5].map(Weight.pounds))
        #expect(weeks.map(\.reps) == [10, 11, 12, 10])
    }

    @Test("Double progression keeps cycling after the range is exhausted")
    func double_rangeExhaustion_repeats() throws {
        let slot = try Fixtures.slot(Fixtures.inclineDB, id: 2, reps: 10, repsHi: 12, progression: .double)
        let weeks = (3 ... 7).map { prescribe(slot, Fixtures.inclineDB, week: $0) }
        #expect(weeks.map(\.load) == [52.5, 52.5, 52.5, 55, 55].map(Weight.pounds))
        #expect(weeks.map(\.reps) == [10, 11, 12, 10, 11])
    }

    @Test("Fixed keeps the start load and reps for the whole block (rule 11)")
    func fixed_loadConstantAcrossBlock() throws {
        let slot = try Fixtures.slot(
            Fixtures.latPulldown,
            id: 3,
            reps: 12,
            progression: .fixed,
            startLoad: .pounds(160)
        )
        let weeks = (0 ..< 7).map { prescribe(slot, Fixtures.latPulldown, week: $0) }
        #expect(Set(weeks.map(\.load)) == [.pounds(160)])
        #expect(Set(weeks.map(\.reps)) == [12])
    }

    @Test("Deload: load × 0.85 to the step, one fewer set, RPE − 2 (rule 12, criterion 4)")
    func deload_loadTimes085RoundedToStep_minusOneSet_minusTwoRPE() throws {
        let slot = try Fixtures.slot(Fixtures.backSquat, id: 4, sets: 5, reps: 5, rpe: 8, rest: 180)
        let deload = prescribe(slot, Fixtures.backSquat, week: 7, deload: true)
        // 250 + 5 × 7 = 285 lb; 285 × 0.85 = 242.25 → nearest 5 lb = 240.
        #expect(prescribe(slot, Fixtures.backSquat, week: 7).load == .pounds(285))
        #expect(deload.load == .pounds(240))
        #expect(deload.sets == 4)
        #expect(try deload.rpe == (Fixtures.rpe(6)))
        #expect(deload.reps == 5)
        #expect(deload.isDeload)
    }

    @Test("Deload never drops below one set or RPE 5")
    func deload_floorsAtOneSetAndRPE5() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 5, sets: 1, reps: 5, rpe: 6)
        let deload = prescribe(slot, Fixtures.bench, week: 1, deload: true)
        #expect(deload.sets == 1)
        #expect(try deload.rpe == (Fixtures.rpe(5)))
    }

    @Test("HELD is set exactly when the previous week was missed (criterion 5)")
    func held_flagSetWhenPreviousWeekMissed() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 6, misses: [1])
        #expect(prescribe(slot, Fixtures.bench, week: 2).isHeld)
        #expect(!prescribe(slot, Fixtures.bench, week: 3).isHeld)
        #expect(!prescribe(slot, Fixtures.bench, week: 1).isHeld)
        #expect(!prescribe(slot, Fixtures.bench, week: 0).isHeld)
    }

    @Test("Kilogram programs use kg steps: 2.5 barbell, 1.25 otherwise, and deload to 2.5 kg (decision #9)")
    func prescribe_kg_usesKgSteps() throws {
        let bench = try Fixtures.slot(Fixtures.bench, id: 7, sets: 5, reps: 5)
        let incline = try Fixtures.slot(Fixtures.inclineDB, id: 8, reps: 10, repsHi: 12, progression: .double)
        #expect(prescribe(bench, Fixtures.bench, week: 2, units: .kg).load == .kilograms(85))
        #expect(prescribe(bench, Fixtures.bench, week: 2, units: .kg).step == .kilograms(2.5))
        #expect(prescribe(incline, Fixtures.inclineDB, week: 3, units: .kg).load == .kilograms(23.75))
        // 80 + 2.5 × 7 = 97.5 kg; × 0.85 = 82.875 → nearest 2.5 kg = 82.5.
        #expect(prescribe(bench, Fixtures.bench, week: 7, deload: true, units: .kg).load == .kilograms(82.5))
    }

    @Test("Kettlebells progress a bell size at a time and deload to the nearest 2 kg / 5 lb (decision #22)")
    func prescribe_kettlebell_usesBellSteps() throws {
        let swing = Fixtures.exercise(30, "Kettlebell Swing", .kettlebell, pounds: 25, kilograms: 12)
        let slot = try Fixtures.slot(swing, id: 10, reps: 10)
        #expect(prescribe(slot, swing, week: 2).load == .pounds(35))
        #expect(prescribe(slot, swing, week: 2, units: .kg).load == .kilograms(16))
        #expect(prescribe(slot, swing, week: 2, units: .kg).step == .kilograms(2))
        // 12 + 2 × 7 = 26 kg; × 0.85 = 22.1 → nearest 2 kg = 22. 25 + 5 × 7 = 60 lb; × 0.85 = 51 → 50.
        #expect(prescribe(slot, swing, week: 7, deload: true, units: .kg).load == .kilograms(22))
        #expect(prescribe(slot, swing, week: 7, deload: true).load == .pounds(50))
    }

    @Test("Seed slots prescribe per spec §7.2", arguments: ProgressionFixtures.rows)
    func prescribe_table(row: ProgressionFixtures.Row) throws {
        let slot = try Fixtures.slot(
            row.exercise, id: 9, sets: row.sets, reps: row.reps, repsHi: row.repsHi, rpe: row.rpe,
            progression: row.progression, step: row.step, misses: row.misses
        )
        let result = prescribe(slot, row.exercise, week: row.week, deload: row.deload)
        #expect(result.load == row.load)
        #expect(result.reps == row.expectedReps)
        #expect(result.sets == row.expectedSets ?? row.sets)
        #expect(result.rpe.value == row.expectedRPE ?? row.rpe)
        #expect(result.isHeld == row.held)
        #expect(result.rest == slot.rest)
        #expect(result.progression == row.progression)
    }
}
