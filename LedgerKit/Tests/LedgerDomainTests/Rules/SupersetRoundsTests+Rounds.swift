import Foundation
@testable import LedgerDomain
import Testing

/// F10 S9 criterion 2: `rounds(block:exercises:)` and `round(of:block:exercises:)` are public, pure and total.
@Suite("SupersetRounds · rounds", .tags(.domain))
struct SupersetRoundsRoundsTests {
    private typealias Ref = SupersetRounds.SetRef

    private func exercise(
        _ index: Int,
        working: Int,
        drop: Bool = false,
        superset: Bool = false
    ) throws -> WorkoutExercise {
        let kinds = Array(repeating: SetKind.working, count: working) + (drop ? [.drop] : [])
        let sets = kinds.enumerated()
            .map { Fixtures.set(index * 100 + $0.offset, pounds: 100, reps: 8, kind: $0.element) }
        return try Fixtures.workoutExercise(Fixtures.bench, index: index, sets: sets, rest: 90, superset: superset)
    }

    private func ref(_ exercise: Int, _ set: Int) -> Ref {
        Ref(exerciseIndex: exercise, setIndex: set)
    }

    @Test("Working rounds, then drop rounds; a member with fewer rows drops out of the later rounds")
    func rounds_workingThenDrop_shortMemberDropsOut() throws {
        let exercises = try [exercise(0, working: 3, drop: true), exercise(1, working: 2, drop: true, superset: true)]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let rounds = SupersetRounds.rounds(block: block, exercises: exercises)
        #expect(rounds == [[ref(0, 0), ref(1, 0)], [ref(0, 1), ref(1, 1)], [ref(0, 2)], [ref(0, 3), ref(1, 2)]])
        #expect(SupersetRounds.displayOrder(block: block, exercises: exercises) == rounds.flatMap(\.self))
    }

    @Test("round(of:) names each row's round from 0; a row the block does not hold has none")
    func roundOf_eachRow_andOutOfRange() throws {
        let exercises = try [exercise(0, working: 3, drop: true), exercise(1, working: 2, drop: true, superset: true)]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        let rounds = SupersetRounds.rounds(block: block, exercises: exercises)
        for (index, round) in rounds.enumerated() {
            for row in round {
                #expect(SupersetRounds.round(of: row, block: block, exercises: exercises) == index)
            }
        }
        #expect(SupersetRounds.round(of: ref(1, 9), block: block, exercises: exercises) == nil)
        #expect(SupersetRounds.round(of: ref(5, 0), block: block, exercises: exercises) == nil)
    }

    @Test("An out-of-range member is skipped, and a block with no row has no round")
    func outOfRangeAndEmpty() throws {
        let exercises = try [exercise(0, working: 2), exercise(1, working: 0, superset: true)]
        let block = try #require(SupersetRounds.blocks(in: exercises).first)
        #expect(SupersetRounds.rounds(block: block, exercises: Array(exercises.prefix(1))) == [
            [ref(0, 0)],
            [ref(0, 1)]
        ])
        #expect(SupersetRounds.rounds(block: block, exercises: []).isEmpty)
        #expect(SupersetRounds.rounds(block: block, exercises: [exercises[1], exercises[1]]).isEmpty)
    }
}
