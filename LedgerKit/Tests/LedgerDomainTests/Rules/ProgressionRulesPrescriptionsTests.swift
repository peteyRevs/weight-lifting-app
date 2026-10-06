import Foundation
@testable import LedgerDomain
import Testing

/// `ProgressionRules.prescriptions`: one slot's prescription in every week of a block, which the Day editor
/// prints as "W1 50 · W2 50 · …" (F11 criterion 7). Expected values are worked by hand from spec §7.2.
/// In its own file because `ProgressionRulesTests.swift` is at the lint's length limit.
@Suite("ProgressionRules.prescriptions", .tags(.domain))
struct ProgressionRulesPrescriptionsTests {
    /// Eight weeks, the last a deload: the spec's seed block.
    private let weeks = (0 ..< 8).map { Fixtures.week($0, deload: $0 == 7) }

    @Test("Incline DB Press reads 50, 50, 50, 52.5, 52.5, 52.5, 55 and a 47.5 lb deload, reps per rule 10")
    func prescriptions_inclineDBPress_followRule10() throws {
        let slot = try Fixtures.upperA().slots[1]
        #expect(slot.startLoad == nil, "the 50 lb come from the exercise")
        let all = ProgressionRules.prescriptions(for: slot, weeks: weeks, exercise: Fixtures.inclineDB, units: .lb)
        // Weeks 1–7: 50 + 2.5 × ⌊adv / 3⌋. Week 8: adv = 7, 55 lb × 0.85 = 46.75 → 47.5 on the 2.5 lb step.
        #expect(all.map(\.load) == [50, 50, 50, 52.5, 52.5, 52.5, 55, 47.5].map(Weight.pounds))
        #expect(all.map(\.reps) == [10, 11, 12, 10, 11, 12, 10, 11])
        #expect(all.map(\.sets) == [3, 3, 3, 3, 3, 3, 3, 2])
        #expect(all.map(\.rpe.value) == [8, 8, 8, 8, 8, 8, 8, 6])
        #expect(all.map(\.isDeload) == [false, false, false, false, false, false, false, true])
        #expect(all.map(\.isHeld) == [false, false, false, false, false, false, false, false])
    }

    @Test("Back Squat's week 8 is the deload: 285 lb × 0.85 → 240 lb, 4 sets, RPE 6 (rule 12)")
    func prescriptions_backSquatWeek8_isTheDeload() throws {
        let slot = try Fixtures.slot(Fixtures.backSquat, id: 4, sets: 5, reps: 5, rest: 180)
        let all = ProgressionRules.prescriptions(for: slot, weeks: weeks, exercise: Fixtures.backSquat, units: .lb)
        #expect(all.map(\.load) == [250, 255, 260, 265, 270, 275, 280, 240].map(Weight.pounds))
        let deload = try #require(all.last)
        #expect(deload.sets == 4)
        #expect(deload.reps == 5)
        #expect(deload.rpe.value == 6)
        #expect(deload.isDeload)
    }

    @Test("A missed week marks the next week as held, and the load does not advance through it")
    func prescriptions_missedWeek_marksTheNextAsHeld() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, sets: 5, reps: 5, misses: [2])
        let all = ProgressionRules.prescriptions(for: slot, weeks: weeks, exercise: Fixtures.bench, units: .lb)
        #expect(all.map(\.isHeld) == [false, false, false, true, false, false, false, false])
        #expect(all.prefix(5).map(\.load) == [180, 185, 190, 190, 195].map(Weight.pounds))
    }

    @Test("Each week is prescribed under its own index, in the order given; no weeks give no prescriptions")
    func prescriptions_useEachWeeksOwnIndex() throws {
        let slot = try Fixtures.slot(Fixtures.bench, id: 1, sets: 5, reps: 5)
        let picked = [Fixtures.week(6), Fixtures.week(0), Fixtures.week(3, deload: true)]
        let some = ProgressionRules.prescriptions(for: slot, weeks: picked, exercise: Fixtures.bench, units: .kg)
        // 80 kg + 2.5 × 6; 80; (80 + 2.5 × 3) × 0.85 = 74.375 → 75 on the 2.5 kg step.
        #expect(some.map(\.load) == [95, 80, 75].map(Weight.kilograms))
        for (week, prescription) in zip(picked, some) {
            let single = ProgressionRules.prescribe(
                week: week, weekIndex: week.index, slot: slot, exercise: Fixtures.bench, units: .kg
            )
            #expect(prescription == single)
        }
        #expect(ProgressionRules.prescriptions(for: slot, weeks: [], exercise: Fixtures.bench, units: .lb).isEmpty)
    }
}
