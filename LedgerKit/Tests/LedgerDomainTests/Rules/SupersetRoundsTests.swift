import Foundation
@testable import LedgerDomain
import Testing

@Suite("SupersetRounds", .tags(.domain))
struct SupersetRoundsTests {
    private typealias Ref = SupersetRounds.SetRef

    /// Rows for one exercise: `working` working sets, then the given extra kinds in order.
    private func exercise(
        _ index: Int,
        working: Int,
        extra: [SetKind] = [],
        rest: Int = 90,
        superset: Bool = false
    ) throws -> WorkoutExercise {
        let kinds = Array(repeating: SetKind.working, count: working) + extra
        let sets = kinds.enumerated()
            .map { Fixtures.set(index * 100 + $0.offset, pounds: 100, reps: 8, kind: $0.element) }
        return try Fixtures.workoutExercise(Fixtures.bench, index: index, sets: sets, rest: rest, superset: superset)
    }

    private func ref(_ exercise: Int, _ set: Int) -> Ref {
        Ref(exerciseIndex: exercise, setIndex: set)
    }

    @Test("Superset rows run round-major A1 B1 A2 B2 A3 B3, then AD (rule 20, criterion 8)")
    func displayOrder_isRoundMajor_A1B1A2B2() throws {
        let exercises = try [exercise(0, working: 3, extra: [.drop]), exercise(1, working: 3, superset: true)]
        let blocks = SupersetRounds.blocks(in: exercises)
        #expect(blocks.map(\.exerciseIndices) == [[0, 1]])
        let order = SupersetRounds.displayOrder(block: blocks[0], exercises: exercises)
        #expect(order == [ref(0, 0), ref(1, 0), ref(0, 1), ref(1, 1), ref(0, 2), ref(1, 2), ref(0, 3)])
    }

    @Test("Drop rows form their own final round, after added sets (rule 20)")
    func dropRows_formTheirOwnFinalRound() throws {
        let exercises = try [
            exercise(0, working: 2, extra: [.drop, .added]),
            exercise(1, working: 2, extra: [.drop], superset: true)
        ]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let order = SupersetRounds.displayOrder(block: block, exercises: exercises)
        #expect(order == [ref(0, 0), ref(1, 0), ref(0, 1), ref(1, 1), ref(0, 3), ref(0, 2), ref(1, 2)])
    }

    @Test("Only the last member of each round is last of round: B1, B2, B3, AD (rule 19, criterion 8)")
    func isLastOfRound_trueOnlyForLastMember() throws {
        let exercises = try [exercise(0, working: 3, extra: [.drop]), exercise(1, working: 3, superset: true)]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let order = SupersetRounds.displayOrder(block: block, exercises: exercises)
        let last = order.filter { SupersetRounds.isLastOfRound($0, block: block, exercises: exercises) }
        #expect(last == [ref(1, 0), ref(1, 1), ref(1, 2), ref(0, 3)])
        #expect(!SupersetRounds.isLastOfRound(ref(2, 0), block: block, exercises: exercises))
    }

    @Test("Group rest is the longest member rest (rule 19, decision #7)")
    func groupRest_isMaxOfMemberRests() throws {
        let exercises = try [exercise(0, working: 3, rest: 90), exercise(1, working: 3, rest: 60, superset: true)]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        #expect(SupersetRounds.groupRest(block: block, exercises: exercises).seconds == 90)
        let outOfRange = SupersetRounds.Block(exerciseIndices: [7])
        #expect(SupersetRounds.groupRest(block: outOfRange, exercises: exercises) == .defaultRest)
    }

    @Test("The longest of the rests handed in is the group's; one rest is its own, and none is the default")
    func groupRestOfRests_isTheLongest() throws {
        let rests = try [75, 60, 120].map { try #require(RestDuration(seconds: $0)) }
        #expect(SupersetRounds.groupRest(of: rests).seconds == 120)
        #expect(SupersetRounds.groupRest(of: [rests[1]]).seconds == 60)
        #expect(SupersetRounds.groupRest(of: []) == .defaultRest)
    }

    @Test("A shorter member drops out of later rounds")
    func unequalSetCounts_shorterMemberLeavesLaterRounds() throws {
        let exercises = try [exercise(0, working: 4), exercise(1, working: 2, superset: true)]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let order = SupersetRounds.displayOrder(block: block, exercises: exercises)
        #expect(order == [ref(0, 0), ref(1, 0), ref(0, 1), ref(1, 1), ref(0, 2), ref(0, 3)])
        let last = order.filter { SupersetRounds.isLastOfRound($0, block: block, exercises: exercises) }
        #expect(last == [ref(1, 0), ref(1, 1), ref(0, 2), ref(0, 3)])
    }

    @Test("A three-member block rotates A B C each round")
    func threeMemberBlock_rotates() throws {
        let exercises = try [
            exercise(0, working: 2),
            exercise(1, working: 2, superset: true),
            exercise(2, working: 2, superset: true)
        ]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let order = SupersetRounds.displayOrder(block: block, exercises: exercises)
        #expect(order == [ref(0, 0), ref(1, 0), ref(2, 0), ref(0, 1), ref(1, 1), ref(2, 1)])
    }

    @Test("Straight exercises are one-member blocks: rows in order, every set last of its round")
    func noSuperset_passesThrough() throws {
        let exercises = try [
            exercise(0, working: 2, superset: true),
            exercise(1, working: 3),
            exercise(2, working: 1, superset: true)
        ]
        let blocks = SupersetRounds.blocks(in: exercises)
        #expect(blocks.map(\.exerciseIndices) == [[0], [1, 2]])
        let order = SupersetRounds.displayOrder(block: blocks[0], exercises: exercises)
        #expect(order == [ref(0, 0), ref(0, 1)])
        #expect(order.allSatisfy { SupersetRounds.isLastOfRound($0, block: blocks[0], exercises: exercises) })
        #expect(SupersetRounds.blocks(in: []).isEmpty)
    }

    @Test("Members are lettered A…E (rule 44), then F…Z, then numbered")
    func letters_AtoE() {
        #expect((0 ..< 5).map(SupersetRounds.letter(forMemberAt:)) == ["A", "B", "C", "D", "E"])
        #expect(SupersetRounds.letter(forMemberAt: 25) == "Z")
        #expect(SupersetRounds.letter(forMemberAt: 26) == "27")
        #expect(SupersetRounds.letter(forMemberAt: -1) == "0")
    }

    @Test("Display order is a permutation of the block's set rows", .tags(.property), arguments: PropertySeed.all)
    func displayOrder_isPermutation(seed: PropertySeed) throws {
        var generator = seed.generator
        let kinds: [SetKind] = [.working, .working, .drop, .added, .warmup]
        let exercises = try (0 ..< Int.random(in: 1 ... 5, using: &generator)).map { index in
            let extra = (0 ..< Int.random(in: 0 ... 3, using: &generator))
                .compactMap { _ in kinds.randomElement(using: &generator) }
            return try exercise(
                index,
                working: Int.random(in: 0 ... 6, using: &generator),
                extra: extra,
                superset: index > 0
            )
        }
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let order = SupersetRounds.displayOrder(block: block, exercises: exercises)
        let all = exercises.indices.flatMap { exerciseIndex in exercises[exerciseIndex].sets.indices.map { ref(
            exerciseIndex,
            $0
        ) } }
        #expect(order.count == all.count)
        #expect(Set(order) == Set(all))
    }
}
