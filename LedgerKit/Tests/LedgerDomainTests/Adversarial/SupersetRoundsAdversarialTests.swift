import Foundation
@testable import LedgerDomain
import Testing

/// One superset member: working rows, drop rows and rest seconds.
struct Member {
    let working: Int
    let drops: Int
    let rest: Int

    init(_ working: Int, _ drops: Int, _ rest: Int) {
        self.working = working
        self.drops = drops
        self.rest = rest
    }
}

@Suite("SupersetRounds (adversarial)", .tags(.domain))
struct SupersetRoundsAdversarialTests {
    /// Members of one superset block: `(working rows, drop rows, rest)` each.
    static func block(_ members: [Member]) throws -> [WorkoutExercise] {
        try members.enumerated().map { index, member in
            try Adversarial.exercise(
                index: index,
                rows: Adversarial.rows(member.working, drops: member.drops, base: index * 1000),
                rest: member.rest,
                superset: index > 0
            )
        }
    }

    /// Rule 20/44 labels: "A1", "B2", "AD".
    static func labels(
        _ refs: [SupersetRounds.SetRef],
        block: SupersetRounds.Block,
        in exercises: [WorkoutExercise]
    ) -> [String] {
        refs.map { ref in
            let position = block.exerciseIndices.firstIndex(of: ref.exerciseIndex) ?? -1
            let letter = SupersetRounds.letter(forMemberAt: position)
            let rows = exercises[ref.exerciseIndex].sets
            if rows[ref.setIndex].kind == .drop {
                return letter + "D"
            }
            return letter + "\(rows[..<ref.setIndex].count(where: { $0.kind != .drop }) + 1)"
        }
    }

    static func order(_ exercises: [WorkoutExercise]) throws -> (order: [String], lasts: [String]) {
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let refs = SupersetRounds.displayOrder(block: block, exercises: exercises)
        let lasts = refs.filter { SupersetRounds.isLastOfRound($0, block: block, exercises: exercises) }
        return (labels(refs, block: block, in: exercises), labels(lasts, block: block, in: exercises))
    }
}

extension SupersetRoundsAdversarialTests {
    @Test("Two 3-set members with a drop on A: A1 B1 A2 B2 A3 B3 AD; last of round B1 B2 B3 AD (criterion 8).")
    func displayOrder_criterion8() throws {
        let result = try Self.order(Self.block([Member(3, 1, 90), Member(3, 0, 60)]))
        #expect(result.order == ["A1", "B1", "A2", "B2", "A3", "B3", "AD"])
        #expect(result.lasts == ["B1", "B2", "B3", "AD"])
    }

    @Test("A longer first member finishes its extra rounds alone.")
    func displayOrder_longerFirstMember() throws {
        let result = try Self.order(Self.block([Member(4, 0, 90), Member(2, 0, 60)]))
        #expect(result.order == ["A1", "B1", "A2", "B2", "A3", "A4"])
        #expect(result.lasts == ["B1", "B2", "A3", "A4"])
    }

    @Test("A longer second member finishes its extra rounds alone.")
    func displayOrder_longerSecondMember() throws {
        let result = try Self.order(Self.block([Member(2, 0, 90), Member(4, 0, 60)]))
        #expect(result.order == ["A1", "B1", "A2", "B2", "B3", "B4"])
        #expect(result.lasts == ["B1", "B2", "B3", "B4"])
    }

    @Test("A three-member block rotates A B C each round.")
    func displayOrder_threeMembers() throws {
        let result = try Self.order(Self.block([Member(3, 0, 60), Member(3, 0, 60), Member(3, 0, 60)]))
        #expect(result.order == ["A1", "B1", "C1", "A2", "B2", "C2", "A3", "B3", "C3"])
        #expect(result.lasts == ["C1", "C2", "C3"])
    }

    @Test("A five-member block letters its members A to E (rule 44).")
    func displayOrder_fiveMembers() throws {
        let result = try Self.order(Self.block(Array(repeating: Member(2, 0, 60), count: 5)))
        #expect(result.order == ["A1", "B1", "C1", "D1", "E1", "A2", "B2", "C2", "D2", "E2"])
        #expect(result.lasts == ["E1", "E2"])
        #expect((0 ..< 5).map(SupersetRounds.letter(forMemberAt:)) == ["A", "B", "C", "D", "E"])
    }

    @Test("Drop rows of several members form one final round: AD BD (rule 20).")
    func displayOrder_dropsOnBothMembers() throws {
        let result = try Self.order(Self.block([Member(2, 1, 90), Member(2, 1, 60)]))
        #expect(result.order == ["A1", "B1", "A2", "B2", "AD", "BD"])
        #expect(result.lasts == ["B1", "B2", "BD"])
    }

    @Test("A drop row on the shorter member still waits for the working rounds to finish.")
    func displayOrder_dropOnShorterMember() throws {
        let result = try Self.order(Self.block([Member(3, 0, 90), Member(2, 1, 60)]))
        #expect(result.order == ["A1", "B1", "A2", "B2", "A3", "BD"])
        #expect(result.lasts == ["B1", "B2", "A3", "BD"])
    }

    @Test("A member with no rows is skipped without breaking the block.")
    func displayOrder_emptyMember() throws {
        let result = try Self.order(Self.block([Member(0, 0, 90), Member(3, 0, 60)]))
        #expect(result.order == ["B1", "B2", "B3"])
        #expect(result.lasts == ["B1", "B2", "B3"])
    }

    @Test("A straight exercise is its own block and every row ends its round.")
    func solo_everyRowIsLastOfRound() throws {
        let exercises = try [Adversarial.exercise(rows: Adversarial.rows(4, drops: 1))]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        #expect(block.exerciseIndices == [0])
        let refs = SupersetRounds.displayOrder(block: block, exercises: exercises)
        #expect(refs.count == 5)
        #expect(refs.allSatisfy { SupersetRounds.isLastOfRound($0, block: block, exercises: exercises) })
        #expect(try SupersetRounds.groupRest(block: block, exercises: exercises) == (Fixtures.rest(90)))
    }

    @Test("Blocks join consecutive superset flags and ignore the first exercise's flag.")
    func blocks_grouping() throws {
        let flags = [true, false, true, true, false, true, false]
        let exercises = try flags.enumerated().map { index, flag in
            try Adversarial.exercise(index: index, rows: Adversarial.rows(1, base: index * 10), superset: flag)
        }
        let blocks = SupersetRounds.blocks(in: exercises).map(\.exerciseIndices)
        #expect(blocks == [[0], [1, 2, 3], [4, 5], [6]])
        #expect(SupersetRounds.blocks(in: []).isEmpty)
    }

    @Test("An empty or out-of-range block falls back to the default rest (documented contract).")
    func groupRest_emptyBlock_isDefault() throws {
        let exercises = try Self.block([Member(3, 0, 150)])
        #expect(SupersetRounds
            .groupRest(block: SupersetRounds.Block(exerciseIndices: []), exercises: exercises) == .defaultRest)
        #expect(SupersetRounds
            .groupRest(block: SupersetRounds.Block(exerciseIndices: [7]), exercises: exercises) == .defaultRest)
    }

    @Test("Group rest is the longest member rest (rule 19, decision #7).")
    func groupRest_isMaxOfMembers() throws {
        let pair = try Self.block([Member(3, 0, 90), Member(3, 0, 60)])
        let triple = try Self.block([Member(3, 0, 60), Member(3, 0, 120), Member(3, 0, 90)])
        let pairBlock = try #require(SupersetRounds.blocks(in: pair).first)
        let tripleBlock = try #require(SupersetRounds.blocks(in: triple).first)
        #expect(try SupersetRounds.groupRest(block: pairBlock, exercises: pair) == (Fixtures.rest(90)))
        #expect(try SupersetRounds.groupRest(block: tripleBlock, exercises: triple) == (Fixtures.rest(120)))
    }
}
