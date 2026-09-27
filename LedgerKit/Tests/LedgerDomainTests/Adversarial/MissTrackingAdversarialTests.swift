import Foundation
@testable import LedgerDomain
import Testing

@Suite("MissTracking (adversarial)", .tags(.domain))
struct MissTrackingAdversarialTests {
    /// One set row for decision #5: reps, kind, done.
    struct Row: Sendable, CustomStringConvertible {
        let reps: Int
        let kind: SetKind
        let done: Bool

        init(_ reps: Int, _ kind: SetKind, _ done: Bool) {
            self.reps = reps
            self.kind = kind
            self.done = done
        }

        var description: String {
            "\(reps) reps \(kind) \(done ? "done" : "undone")"
        }
    }

    static func slot(misses: Set<Int> = []) throws -> Slot {
        try Fixtures.slot(Fixtures.bench, id: 1600, sets: 5, reps: 5, misses: misses)
    }

    /// Weight is irrelevant to decision #5, so every row uses `weight`.
    static func exercise(
        _ rows: [Row],
        targetSets: Int = 5,
        weight: Weight = pounds("185")
    ) throws -> WorkoutExercise {
        try Adversarial.exercise(
            rows: rows.enumerated().map { Adversarial.row(
                $0,
                weight: weight,
                reps: $1.reps,
                kind: $1.kind,
                done: $1.done
            ) },
            targetSets: targetSets,
            targetReps: 5
        )
    }

    static func fiveByFive(_ override: [Int: Row] = [:], extra: [Row] = []) -> [Row] {
        (0 ..< 5).map { override[$0] ?? Row(5, .working, true) } + extra
    }

    static func update(
        _ rows: [Row],
        misses: Set<Int> = [],
        week: Int = 3,
        deload: Bool = false
    ) throws -> Set<Int> {
        try MissTracking.update(slot: slot(misses: misses), exercise: exercise(rows), weekIndex: week, isDeload: deload)
            .misses
    }
}

extension MissTrackingAdversarialTests {
    @Test("Set 2 logged at 4 of 5 reps inserts the week (criterion 11, decision #5).")
    func shortWorkingSet_insertsWeek() throws {
        #expect(try Self.update(Self.fiveByFive([1: Row(4, .working, true)])) == [3])
    }

    @Test("The same miss in a deload week leaves the slot exactly as it was (criterion 11).")
    func deload_leavesSlotUnchanged() throws {
        let slot = try Self.slot(misses: [1])
        let short = try Self.exercise(Self.fiveByFive([1: Row(4, .working, true)]))
        #expect(MissTracking.update(slot: slot, exercise: short, weekIndex: 3, isDeload: true) == slot)
        let prior = try Self.slot(misses: [3])
        let clean = try Self.exercise(Self.fiveByFive())
        #expect(MissTracking.update(slot: prior, exercise: clean, weekIndex: 3, isDeload: true) == prior)
    }

    @Test(
        "A short or undone drop, added or warm-up set alone never inserts the week (criterion 11).",
        arguments: [
            Row(2, .drop, true), Row(0, .drop, false), Row(1, .added, true), Row(5, .added, false),
            Row(1, .warmup, true), Row(3, .warmup, false)
        ]
    )
    func nonWorkingShortfall_doesNotInsert(row: Row) throws {
        #expect(try Self.update(Self.fiveByFive(extra: [row])).isEmpty)
    }

    @Test("An undone working set is a miss.")
    func undoneWorkingSet_isMiss() throws {
        #expect(try Self.update(Self.fiveByFive([4: Row(5, .working, false)])) == [3])
    }

    @Test("Fewer working rows than prescribed is a miss even when every row was done.")
    func fewerWorkingRows_isMiss() throws {
        let rows = Array(Self.fiveByFive().prefix(4))
        #expect(try Self.update(rows) == [3])
    }

    @Test("Drop and added sets cannot mask a short or missing working set (decision #5 vs spec §7.2 note).")
    func nonWorkingSets_cannotMaskMiss() throws {
        #expect(try Self.update(Self.fiveByFive([2: Row(3, .working, true)], extra: [Row(8, .drop, true)])) == [3])
        let fourPlusAdded = Array(Self.fiveByFive().prefix(4)) + [Row(5, .added, true)]
        #expect(try Self.update(fourPlusAdded) == [3])
    }

    @Test("Extra working sets and reps above target are not misses; neither is a lighter load at full reps.")
    func surplus_isNotMiss() throws {
        #expect(try Self.update(Self.fiveByFive(extra: [Row(5, .working, true)])).isEmpty)
        #expect(try Self.update(Self.fiveByFive([0: Row(8, .working, true)])).isEmpty)
        let light = try Self.exercise(Self.fiveByFive(), weight: pounds("95"))
        #expect(try MissTracking.update(slot: Self.slot(), exercise: light, weekIndex: 3, isDeload: false).misses
            .isEmpty)
    }

    @Test("A clean week removes that week's earlier miss and keeps the others (rule 13).")
    func cleanWeek_removesPriorMiss() throws {
        #expect(try Self.update(Self.fiveByFive(), misses: [1, 3]) == [1])
        #expect(try Self.update(Self.fiveByFive(), misses: [1]) == [1])
        #expect(try Self.update(Self.fiveByFive([0: Row(1, .working, true)]), misses: [1, 3]) == [1, 3])
    }

    @Test("Only misses change; every other slot field is untouched.")
    func update_changesOnlyMisses() throws {
        let slot = try Self.slot()
        var updated = try MissTracking.update(
            slot: slot, exercise: Self.exercise(Self.fiveByFive([0: Row(1, .working, true)])), weekIndex: 6,
            isDeload: false
        )
        #expect(updated.misses == [6])
        updated.misses = []
        #expect(updated == slot)
    }

    @Test("A skipped week is a miss for every slot; deload and out-of-block weeks change nothing (decision #18).")
    func recordSkippedWeek_marksEverySlot() throws {
        let program = try Fixtures.program(days: [Fixtures.upperA(), Fixtures.upperB()])
        let skipped = MissTracking.recordSkippedWeek(2, in: program)
        #expect(skipped.days.flatMap(\.slots).allSatisfy { $0.misses == [2] })
        #expect(skipped.days.flatMap(\.slots).count == 6)
        #expect(MissTracking.recordSkippedWeek(7, in: program) == program)
        #expect(MissTracking.recordSkippedWeek(8, in: program) == program)
        #expect(MissTracking.recordSkippedWeek(-1, in: program) == program)
        #expect(MissTracking.recordSkippedWeek(2, in: skipped) == skipped)
    }
}

@Suite("MissTracking properties (adversarial)", .tags(.domain, .property))
struct MissTrackingPropertyAdversarialTests {}

extension MissTrackingPropertyAdversarialTests {
    @Test("update matches the decision #5 oracle, is idempotent and ignores row order.", arguments: PropertySeed.all)
    func update_oracleIdempotentOrderFree(seed: PropertySeed) throws {
        var generator = seed.generator
        let kinds: [SetKind] = [.working, .working, .working, .drop, .added, .warmup]
        let rows = (0 ..< Int.random(in: 0 ... 9, using: &generator)).map { _ in
            MissTrackingAdversarialTests.Row(
                Int.random(in: 1 ... 7, using: &generator),
                kinds.randomElement(using: &generator) ?? .working,
                Int.random(in: 0 ..< 5, using: &generator) > 0
            )
        }
        let targetSets = Int.random(in: 1 ... 6, using: &generator)
        let week = Int.random(in: 0 ... 7, using: &generator)
        let prior = Set((0 ... 7).filter { _ in Bool.random(using: &generator) })
        let slot = try MissTrackingAdversarialTests.slot(misses: prior)
        let working = rows.filter { $0.kind == .working }
        let missed = working.contains { !$0.done || $0.reps < 5 } || working.count(where: \.done) < targetSets
        let expected = missed ? prior.union([week]) : prior.subtracting([week])
        let once = try MissTracking.update(
            slot: slot, exercise: MissTrackingAdversarialTests.exercise(rows, targetSets: targetSets), weekIndex: week,
            isDeload: false
        )
        #expect(once.misses == expected, "\(rows) target \(targetSets)")
        let twice = try MissTracking.update(
            slot: once, exercise: MissTrackingAdversarialTests.exercise(rows, targetSets: targetSets), weekIndex: week,
            isDeload: false
        )
        #expect(twice == once)
        let shuffled = try MissTracking.update(
            slot: slot,
            exercise: MissTrackingAdversarialTests.exercise(rows.shuffled(using: &generator), targetSets: targetSets),
            weekIndex: week,
            isDeload: false
        )
        #expect(shuffled.misses == expected)
    }
}
