import Foundation
@testable import LedgerDomain
import Testing

@Suite("TimeEstimate (adversarial)", .tags(.domain))
struct TimeEstimateAdversarialTests {
    /// One slot of a test day.
    struct Row: CustomStringConvertible {
        let sets: Int
        let rest: Int
        let superset: Bool
        let drop: Int

        init(_ sets: Int, _ rest: Int, _ superset: Bool, _ drop: Int) {
            self.sets = sets
            self.rest = rest
            self.superset = superset
            self.drop = drop
        }

        var description: String {
            "\(sets)×\(rest)s\(superset ? " sup" : "")\(drop > 0 ? " +drop" : "")"
        }
    }

    static func day(_ rows: [Row]) throws -> DayTemplate {
        let slots = try rows.enumerated().map { index, row in
            try Fixtures.slot(
                Fixtures.bench, id: 1400 + index, sets: row.sets, reps: 5, rest: row.rest, superset: row.superset,
                dropSets: row.drop
            )
        }
        return DayTemplate(id: DayTemplateID(Fixtures.uuid(1499)), name: "Day", tag: "DY", slots: slots)
    }

    static func prescriptions(_ day: DayTemplate, week: Int = 0, deload: Bool = false) -> [SlotID: Prescription] {
        Dictionary(uniqueKeysWithValues: day.slots.map { slot in
            (slot.id, ProgressionRulesAdversarialTests.prescribe(slot, Fixtures.bench, week: week, deload: deload))
        })
    }

    static func minutes(_ day: DayTemplate, deload: Bool = false) -> Int {
        TimeEstimate.minutes(day: day, prescriptions: prescriptions(day, deload: deload))
    }
}

extension TimeEstimateAdversarialTests {
    @Test("Five straight slots: Σ sets × (42 + rest) = 2,541 s → 42 min (criterion 9, decision #14).")
    func minutes_fiveStraightSlots_criterion9() throws {
        // 5×192 + 3×132 + 4×132 + 3×117 + 3×102 = 960 + 396 + 528 + 351 + 306 = 2,541 s = 42.35 min → 42.
        let day = try Self.day([
            Row(5, 150, false, 0),
            Row(3, 90, false, 0),
            Row(4, 90, false, 0),
            Row(3, 75, false, 0),
            Row(3, 60, false, 0)
        ])
        #expect(Self.minutes(day) == 42)
        #expect(TimeEstimate.minutes(day: day, prescriptions: [:]) == 42)
    }

    @Test("A superset of two 3-set slots rests 3 × 90 s: 252 + 270 = 522 s → 9 min (criterion 9).")
    func minutes_superset_countsRoundRestOnce() throws {
        let day = try Self.day([Row(3, 90, false, 0), Row(3, 60, true, 0)])
        #expect(Self.minutes(day) == 9)
    }

    @Test("The seed Upper A day is 2,361 s → 39 min (its last two slots are a superset).")
    func minutes_seedUpperA() throws {
        // 960 + 396 + 528 + 6 × 42 + 3 × max(75, 60) = 960 + 396 + 528 + 252 + 225 = 2,361 s → 39.35 → 39.
        let day = try Fixtures.upperA()
        #expect(TimeEstimate.minutes(day: day, prescriptions: [:]) == 39)
    }

    @Test("A drop set is one more set with its own rest: 4 × 102 = 408 s → 7 min.")
    func minutes_dropSetCounted() throws {
        #expect(try TimeEstimate.minutes(day: Fixtures.upperB(), prescriptions: [:]) == 7)
    }

    @Test("A drop set inside a superset adds one more round of group rest: 294 + 4 × 90 = 654 s → 11 min.")
    func minutes_supersetWithDrop() throws {
        let day = try Self.day([Row(3, 90, false, 1), Row(3, 60, true, 0)])
        #expect(Self.minutes(day) == 11)
    }

    @Test("A three-member superset rests once per round for its longest rest: 378 + 360 = 738 s → 12 min.")
    func minutes_threeMemberSuperset() throws {
        let day = try Self.day([Row(3, 60, false, 0), Row(3, 90, true, 0), Row(3, 120, true, 0)])
        #expect(Self.minutes(day) == 12)
    }

    @Test("An unequal superset (4 and 2 sets) rests over four rounds: ≈ 9 min either way it is read.")
    func minutes_unequalSuperset() throws {
        // 6 × 42 = 252; 4 rounds × 75 = 300 → 552 s (9.2) — or 2 × 75 + 2 × 60 → 522 s (8.7). Both → 9.
        let day = try Self.day([Row(4, 60, false, 0), Row(2, 75, true, 0)])
        #expect(Self.minutes(day) == 9)
    }

    @Test("Deload prescriptions have one fewer set: bench 5 → 4 sets, 960 s → 768 s (16 → 13 min).")
    func minutes_deloadUsesPrescriptionSets() throws {
        let day = try Self.day([Row(5, 150, false, 0)])
        #expect(Self.minutes(day) == 16)
        #expect(Self.minutes(day, deload: true) == 13)
    }

    @Test("Half minutes round up: 5 × 102 = 510 s → 9 min; 5 × 162 = 810 s → 14 min.")
    func minutes_halfMinute_roundsUp() throws {
        #expect(try Self.minutes(Self.day([Row(5, 60, false, 0)])) == 9)
        #expect(try Self.minutes(Self.day([Row(5, 120, false, 0)])) == 14)
    }

    @Test("An empty day is 0 minutes.")
    func minutes_emptyDay_isZero() throws {
        #expect(try Self.minutes(Self.day([])) == 0)
    }

    @Test("A first slot marked superset-with-previous is still straight.")
    func minutes_leadingSupersetFlag_isIgnored() throws {
        let flagged = try Self.day([Row(3, 90, true, 0), Row(3, 60, false, 0)])
        let plain = try Self.day([Row(3, 90, false, 0), Row(3, 60, false, 0)])
        #expect(Self.minutes(flagged) == Self.minutes(plain))
    }
}

@Suite("TimeEstimate properties (adversarial)", .tags(.domain, .property))
struct TimeEstimatePropertyAdversarialTests {}

extension TimeEstimatePropertyAdversarialTests {
    @Test("minutes equals the decision #14 oracle for random days.", arguments: PropertySeed.all)
    func minutes_matchesOracle(seed: PropertySeed) throws {
        var generator = seed.generator
        let rows = (0 ..< Int.random(in: 0 ... 8, using: &generator)).map { _ in
            TimeEstimateAdversarialTests.Row(
                Int.random(in: 1 ... 12, using: &generator),
                30 + 15 * Int.random(in: 0 ... 18, using: &generator),
                Bool.random(using: &generator),
                Int.random(in: 0 ... 1, using: &generator)
            )
        }
        let day = try TimeEstimateAdversarialTests.day(rows)
        // Oracle: work = Σ (sets + drop) × 42; each block rests max(rest) × (max(sets) + any drop ? 1 : 0).
        var seconds = 0
        var block: [TimeEstimateAdversarialTests.Row] = []
        func flush() {
            guard !block.isEmpty else { return }
            let rounds = (block.map(\.sets).max() ?? 0) + (block.contains { $0.drop > 0 } ? 1 : 0)
            seconds += rounds * (block.map(\.rest).max() ?? 0)
            block = []
        }
        for (index, row) in rows.enumerated() {
            if index == 0 || !row.superset {
                flush()
            }
            block.append(row)
            seconds += (row.sets + row.drop) * 42
        }
        flush()
        #expect(TimeEstimate.minutes(day: day, prescriptions: [:]) == (seconds + 30) / 60, "\(rows)")
    }
}
