import Foundation
@testable import LedgerDomain
import Testing

/// Decision #3 as an oracle. History always holds an entry at 20 reps so every rep count has
/// something "at ≥ the same reps" to beat (the no-history case is a recorded spec question).
@Suite("PersonalRecords properties (adversarial)", .tags(.domain, .property))
struct PersonalRecordsPropertyAdversarialTests {
    struct Scenario {
        let rows: [LoggedSet]
        let bestE1RM: Weight
        let atReps: [Reps: Weight]

        var counted: [LoggedSet] {
            rows.filter { $0.isDone && ($0.kind == .working || $0.kind == .added) }
        }

        func detect(
            _ rows: [LoggedSet]? = nil,
            deload: Bool = false,
            e1RM: Weight? = nil,
            history: [Reps: Weight]? = nil
        ) throws -> [PersonalRecord] {
            try PersonalRecords.detect(
                workout: Fixtures.workout([Adversarial.exercise(rows: rows ?? self.rows)], isDeload: deload),
                bestE1RM: [Fixtures.bench.id: e1RM ?? bestE1RM],
                bestWeightAtReps: [Fixtures.bench.id: history ?? atReps],
                now: Fixtures.now
            )
        }
    }

    static func scenario(using generator: inout SeededGenerator) throws -> Scenario {
        let kinds: [SetKind] = [.working, .working, .working, .added, .drop, .warmup]
        let rows = (0 ..< Int.random(in: 1 ... 8, using: &generator)).map { number in
            Adversarial.row(
                number,
                weight: .pounds(randomMultiple(of: 5, in: 9 ... 80, using: &generator)),
                reps: Int.random(in: 1 ... 15, using: &generator),
                kind: kinds.randomElement(using: &generator) ?? .working,
                done: Int.random(in: 0 ..< 4, using: &generator) > 0
            )
        }
        var atReps = try [Fixtures.reps(20): Weight.pounds(randomMultiple(of: 5, in: 0 ... 40, using: &generator))]
        for _ in 0 ..< Int.random(in: 0 ... 5, using: &generator) {
            try atReps[Fixtures.reps(Int.random(in: 1 ... 15, using: &generator))] = .pounds(randomMultiple(
                of: 5,
                in: 9 ... 80,
                using: &generator
            ))
        }
        return Scenario(
            rows: rows,
            bestE1RM: .pounds(randomMultiple(of: 5, in: 9 ... 90, using: &generator)),
            atReps: atReps
        )
    }

    static func isE1RM(_ record: PersonalRecord) -> Bool {
        if case .estimatedOneRepMax = record.kind {
            true
        } else {
            false
        }
    }
}

extension PersonalRecordsPropertyAdversarialTests {
    @Test("detect fires each PR kind exactly when the decision #3 oracle says so.", arguments: PropertySeed.all)
    func detect_matchesOracle(seed: PropertySeed) throws {
        var generator = seed.generator
        let scenario = try Self.scenario(using: &generator)
        let records = try scenario.detect()
        let bestEstimate = scenario.counted.compactMap { OneRepMax.brzycki(weight: $0.weight, reps: $0.reps) }.max()
        let e1RMRecords = records.filter(Self.isE1RM)
        if let bestEstimate, bestEstimate > scenario.bestE1RM {
            #expect(e1RMRecords.map(\.kind) == [.estimatedOneRepMax(bestEstimate)], "\(scenario)")
        } else {
            #expect(e1RMRecords.isEmpty, "\(scenario)")
        }
        let beatsHistory = scenario.counted.contains { set in
            let best = scenario.atReps.filter { $0.key >= set.reps }.map(\.value).max()
            return best.map { set.weight > $0 } ?? false
        }
        #expect(records.contains { !Self.isE1RM($0) } == beatsHistory, "\(scenario)")
        #expect(records.allSatisfy { $0.achievedAt == Fixtures.now && $0.workoutID == Fixtures.workoutID })
    }

    @Test("PRs do not depend on set order, and a deload workout has none.", arguments: PropertySeed.all)
    func detect_orderFreeAndDeloadEmpty(seed: PropertySeed) throws {
        var generator = seed.generator
        let scenario = try Self.scenario(using: &generator)
        #expect(try Set(scenario.detect()) == Set(scenario.detect(scenario.rows.shuffled(using: &generator))))
        #expect(try scenario.detect(deload: true).isEmpty)
    }

    @Test(
        "Once history absorbs a workout's own bests, the same workout sets no PRs (ties are not PRs).",
        arguments: PropertySeed.all
    )
    func detect_afterAbsorbingBests_isEmpty(seed: PropertySeed) throws {
        var generator = seed.generator
        let scenario = try Self.scenario(using: &generator)
        let estimates = scenario.counted.compactMap { OneRepMax.brzycki(weight: $0.weight, reps: $0.reps) }
        let e1RM = max(scenario.bestE1RM, estimates.max() ?? .zero)
        var history = scenario.atReps
        for set in scenario.counted {
            history[set.reps] = max(history[set.reps] ?? .zero, set.weight)
        }
        #expect(try scenario.detect(e1RM: e1RM, history: history).isEmpty, "\(scenario)")
    }
}
