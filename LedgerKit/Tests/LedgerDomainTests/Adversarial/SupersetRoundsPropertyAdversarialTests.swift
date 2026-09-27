import Foundation
@testable import LedgerDomain
import Testing

/// Rule 20 as an oracle: working round r holds every member's r-th non-drop row (member order),
/// then drop round r holds every member's r-th drop row; the last ref of each round ends it.
@Suite("SupersetRounds properties (adversarial)", .tags(.domain, .property))
struct SupersetRoundsPropertyAdversarialTests {
    static func oracle(_ block: SupersetRounds.Block, _ exercises: [WorkoutExercise]) -> [[SupersetRounds.SetRef]] {
        func rounds(_ isDrop: Bool) -> [[SupersetRounds.SetRef]] {
            let columns = block.exerciseIndices.map { index in
                exercises[index].sets.indices
                    .filter { (exercises[index].sets[$0].kind == .drop) == isDrop }
                    .map { SupersetRounds.SetRef(exerciseIndex: index, setIndex: $0) }
            }
            let depth = columns.map(\.count).max() ?? 0
            return (0 ..< depth).map { round in columns.compactMap { round < $0.count ? $0[round] : nil } }
        }
        return rounds(false) + rounds(true)
    }

    /// 1–7 exercises, 0–6 working rows, 0–1 drop row, random superset chaining around them.
    static func randomExercises(using generator: inout SeededGenerator) throws -> [WorkoutExercise] {
        let count = Int.random(in: 1 ... 7, using: &generator)
        return try (0 ..< count).map { index in
            try Adversarial.exercise(
                index: index,
                rows: Adversarial.rows(
                    Int.random(in: 0 ... 6, using: &generator),
                    drops: Int.random(in: 0 ... 1, using: &generator),
                    base: index * 1000
                ),
                rest: [30, 60, 90, 150].randomElement(using: &generator) ?? 90,
                superset: Bool.random(using: &generator)
            )
        }
    }
}

extension SupersetRoundsPropertyAdversarialTests {
    @Test("displayOrder is exactly the round-major oracle order for random blocks.", arguments: PropertySeed.all)
    func displayOrder_matchesOracle(seed: PropertySeed) throws {
        var generator = seed.generator
        let exercises = try Self.randomExercises(using: &generator)
        for block in SupersetRounds.blocks(in: exercises) {
            let expected = Self.oracle(block, exercises)
            let actual = SupersetRounds.displayOrder(block: block, exercises: exercises)
            #expect(actual == Array(expected.joined()))
            let lasts = Set(expected.compactMap(\.last))
            for ref in actual {
                #expect(SupersetRounds.isLastOfRound(ref, block: block, exercises: exercises) == lasts.contains(ref))
            }
        }
    }

    @Test("displayOrder is a permutation of every set ref in the block.", arguments: PropertySeed.all)
    func displayOrder_isPermutation(seed: PropertySeed) throws {
        var generator = seed.generator
        let exercises = try Self.randomExercises(using: &generator)
        for block in SupersetRounds.blocks(in: exercises) {
            let all = block.exerciseIndices.flatMap { index in
                exercises[index].sets.indices.map { SupersetRounds.SetRef(exerciseIndex: index, setIndex: $0) }
            }
            let order = SupersetRounds.displayOrder(block: block, exercises: exercises)
            #expect(order.count == all.count)
            #expect(Set(order) == Set(all))
        }
    }

    @Test(
        "blocks partition the exercises into contiguous runs split at non-superset members.",
        arguments: PropertySeed.all
    )
    func blocks_partitionContiguously(seed: PropertySeed) throws {
        var generator = seed.generator
        let exercises = try Self.randomExercises(using: &generator)
        let blocks = SupersetRounds.blocks(in: exercises)
        #expect(blocks.flatMap(\.exerciseIndices) == Array(exercises.indices))
        for block in blocks {
            let first = try #require(block.exerciseIndices.first)
            #expect(first == 0 || !exercises[first].isSupersetWithPrevious)
            #expect(block.exerciseIndices.dropFirst().allSatisfy { exercises[$0].isSupersetWithPrevious })
            let rest = SupersetRounds.groupRest(block: block, exercises: exercises)
            #expect(rest == block.exerciseIndices.map { exercises[$0].rest }.max())
        }
    }
}
