import Foundation
@testable import LedgerDomain
import Testing

/// Spec §7.2 linear row: misses, week index → expected load and held flag.
struct MissCase: Sendable, CustomStringConvertible {
    let misses: Set<Int>
    let week: Int
    let load: String
    let held: Bool

    init(_ misses: Set<Int>, _ week: Int, _ load: String, _ held: Bool) {
        self.misses = misses
        self.week = week
        self.load = load
        self.held = held
    }

    var description: String {
        "misses \(misses.sorted()) week \(week)"
    }
}

/// Rule 12 row: sets and RPE before → after a deload.
struct FloorCase: Sendable, CustomStringConvertible {
    let sets: Int
    let rpe: String
    let deloadSets: Int
    let deloadRPE: String

    init(_ sets: Int, _ rpe: String, _ deloadSets: Int, _ deloadRPE: String) {
        self.sets = sets
        self.rpe = rpe
        self.deloadSets = deloadSets
        self.deloadRPE = deloadRPE
    }

    var description: String {
        "\(sets) sets @ RPE \(rpe)"
    }
}

@Suite("ProgressionRules (adversarial)", .tags(.domain))
struct ProgressionRulesAdversarialTests {
    static func prescribe(
        _ slot: Slot,
        _ exercise: Exercise,
        week: Int,
        deload: Bool = false,
        units: Units = .lb
    ) -> Prescription {
        ProgressionRules.prescribe(
            week: Fixtures.week(week, deload: deload),
            weekIndex: week,
            slot: slot,
            exercise: exercise,
            units: units
        )
    }

    static func incline(misses: Set<Int> = []) throws -> Slot {
        try Fixtures.slot(
            Fixtures.inclineDB, id: 900, sets: 3, reps: 10, repsHi: 12,
            progression: .double, startLoad: pounds("50"), step: pounds("2.5"), misses: misses
        )
    }

    static func squat(misses: Set<Int> = [], rpe: Decimal = 8) throws -> Slot {
        try Fixtures.slot(
            Fixtures.backSquat, id: 901, sets: 5, reps: 5, rpe: rpe,
            startLoad: pounds("250"), step: pounds("5"), misses: misses
        )
    }
}

extension ProgressionRulesAdversarialTests {
    @Test("Double progression climbs 50×10, 50×11, 50×12, 52.5×10 and keeps cycling (criterion 3, rule 10).")
    func double_incline_matchesCriterion3AndBeyond() throws {
        let slot = try Self.incline()
        let expected: [(String, Int)] = [
            ("50", 10), ("50", 11), ("50", 12), ("52.5", 10), ("52.5", 11), ("52.5", 12), ("55", 10), ("55", 11)
        ]
        for (week, row) in expected.enumerated() {
            let prescription = Self.prescribe(slot, Fixtures.inclineDB, week: week)
            #expect(prescription.load == pounds(row.0), "week \(week)")
            #expect(prescription.reps == row.1, "week \(week)")
            #expect(prescription.sets == 3)
            #expect(!prescription.isHeld)
        }
    }

    @Test("Back Squat deload at week 7: 285 lb → 240 lb, 4 sets, RPE 6 (criterion 4, rule 12).")
    func deload_backSquat_matchesCriterion4() throws {
        let prescription = try Self.prescribe(Self.squat(), Fixtures.backSquat, week: 7, deload: true)
        #expect(prescription.load == pounds("240"))
        #expect(prescription.sets == 4)
        #expect(prescription.reps == 5)
        #expect(try prescription.rpe == (Fixtures.rpe(6)))
        #expect(prescription.isDeload)
        #expect(prescription.step == pounds("5"))
    }

    @Test("misses {1}: week 3 advances twice and is not held; week 2 is held (criterion 5).")
    func linear_missInWeek1_matchesCriterion5() throws {
        let slot = try Self.squat(misses: [1])
        let week3 = Self.prescribe(slot, Fixtures.backSquat, week: 3)
        #expect(week3.load == pounds("260"))
        #expect(!week3.isHeld)
        let week2 = Self.prescribe(slot, Fixtures.backSquat, week: 2)
        #expect(week2.load == pounds("255"))
        #expect(week2.isHeld)
    }

    @Test(
        "Linear advancement counts only earlier, unmissed weeks (spec §7.2 adv).",
        arguments: [
            MissCase([3, 5], 3, "265", false), MissCase([3, 5], 4, "265", true), MissCase([0, 1, 2], 3, "250", true),
            MissCase([0], 1, "250", true), MissCase([], 0, "250", false), MissCase([0, 2, 4, 6], 7, "265", true),
            MissCase([7], 7, "285", false)
        ]
    )
    func linear_misses_table(row: MissCase) throws {
        let prescription = try Self.prescribe(Self.squat(misses: row.misses), Fixtures.backSquat, week: row.week)
        #expect(prescription.load == pounds(row.load))
        #expect(prescription.isHeld == row.held)
    }

    @Test("Double progression with a miss holds reps and load for that week.")
    func double_withMiss_holds() throws {
        let slot = try Self.incline(misses: [1])
        let week3 = Self.prescribe(slot, Fixtures.inclineDB, week: 3)
        #expect(week3.load == pounds("50"))
        #expect(week3.reps == 12)
        let week4 = Self.prescribe(slot, Fixtures.inclineDB, week: 4)
        #expect(week4.load == pounds("52.5"))
        #expect(week4.reps == 10)
    }

    @Test("The narrowest double range (repsHi = reps + 1) alternates reps and steps every two weeks.")
    func double_narrowestSpan_alternates() throws {
        let slot = try Fixtures.slot(
            Fixtures.inclineDB, id: 902, reps: 8, repsHi: 9, progression: .double, startLoad: pounds("40"),
            step: pounds("2.5")
        )
        let rows = (0 ..< 5).map { Self.prescribe(slot, Fixtures.inclineDB, week: $0) }
        #expect(rows.map(\.reps) == [8, 9, 8, 9, 8])
        #expect(rows.map(\.load) == [pounds("40"), pounds("40"), pounds("42.5"), pounds("42.5"), pounds("45")])
    }

    @Test("The widest double range (1…40) climbs 40 weeks before the load moves.")
    func double_widestSpan_exhaustsAtFortyWeeks() throws {
        let slot = try Fixtures.slot(
            Fixtures.inclineDB, id: 903, reps: 1, repsHi: 40, progression: .double, startLoad: pounds("20"),
            step: pounds("2.5")
        )
        let week39 = Self.prescribe(slot, Fixtures.inclineDB, week: 39)
        #expect(week39.reps == 40)
        #expect(week39.load == pounds("20"))
        let week40 = Self.prescribe(slot, Fixtures.inclineDB, week: 40)
        #expect(week40.reps == 1)
        #expect(week40.load == pounds("22.5"))
    }

    @Test("Fixed progression keeps load and reps constant whatever the misses (rule 11).")
    func fixed_constantAcrossBlock() throws {
        let slot = try Fixtures.slot(
            Fixtures.latPulldown, id: 904, reps: 12, progression: .fixed, startLoad: pounds("100"), misses: [2, 5]
        )
        for week in 0 ..< 12 {
            let prescription = Self.prescribe(slot, Fixtures.latPulldown, week: week)
            #expect(prescription.load == pounds("100"), "week \(week)")
            #expect(prescription.reps == 12)
            #expect(prescription.isHeld == [3, 6].contains(week), "week \(week)")
        }
    }

    @Test(
        "Deload floors sets at 1 and RPE at 5 (rule 12, decision #3).",
        arguments: [
            FloorCase(1, "8", 1, "6"), FloorCase(2, "8", 1, "6"), FloorCase(3, "5", 2, "5"), FloorCase(3, "6", 2, "5"),
            FloorCase(3, "6.5", 2, "5"), FloorCase(3, "7", 2, "5"), FloorCase(3, "7.5", 2, "5.5"), FloorCase(
                12,
                "10",
                11,
                "8"
            )
        ]
    )
    func deload_floors(row: FloorCase) throws {
        let (sets, rpe, deloadSets, deloadRPE) = (row.sets, row.rpe, row.deloadSets, row.deloadRPE)
        let slot = try Fixtures.slot(
            Fixtures.backSquat,
            id: 905,
            sets: sets,
            reps: 5,
            rpe: dec(rpe),
            startLoad: pounds("200")
        )
        let prescription = Self.prescribe(slot, Fixtures.backSquat, week: 0, deload: true)
        #expect(prescription.sets == deloadSets)
        #expect(try prescription.rpe == (Fixtures.rpe(dec(deloadRPE))))
    }
}
