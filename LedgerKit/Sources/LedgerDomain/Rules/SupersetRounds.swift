import Foundation

/// Superset blocks, their round-major display order and group rest (rules 19, 20, 44; decision #6).
///
/// A straight exercise is a one-member block, so every one of its sets is the last of its round.
public enum SupersetRounds {
    /// Consecutive exercises joined by `isSupersetWithPrevious` (the first exercise's flag is ignored).
    public struct Block: Hashable, Sendable {
        public let exerciseIndices: [Int]

        init(exerciseIndices: [Int]) {
            self.exerciseIndices = exerciseIndices
        }
    }

    /// A set row: `exercises[exerciseIndex].sets[setIndex]`.
    public struct SetRef: Hashable, Sendable {
        public let exerciseIndex: Int
        public let setIndex: Int

        public init(exerciseIndex: Int, setIndex: Int) {
            self.exerciseIndex = exerciseIndex
            self.setIndex = setIndex
        }
    }

    /// Rule 44 grouping: exercise `i > 0` joins the previous block when it is a superset with the previous.
    public static func blocks(in exercises: [WorkoutExercise]) -> [Block] {
        groups(joiningPrevious: exercises.map(\.isSupersetWithPrevious)).map(Block.init)
    }

    /// Rule 20: round-major order A1 B1 A2 B2 …; a member with fewer rows drops out of later
    /// rounds; drop rows (`.drop`) then form their own final round(s): AD BD.
    public static func displayOrder(block: Block, exercises: [WorkoutExercise]) -> [SetRef] {
        rounds(block: block, exercises: exercises).flatMap(\.self)
    }

    /// Rule 19: `true` when `ref` is the last row of its round (the row after which group rest starts).
    public static func isLastOfRound(_ ref: SetRef, block: Block, exercises: [WorkoutExercise]) -> Bool {
        rounds(block: block, exercises: exercises).contains { $0.last == ref }
    }

    /// Rule 19 / decision #7: a superset rests once per round for the longest member rest.
    /// An empty or out-of-range block falls back to the default rest.
    public static func groupRest(block: Block, exercises: [WorkoutExercise]) -> RestDuration {
        groupRest(of: members(of: block, in: exercises).map(\.rest))
    }

    /// Rule 19 / decision #7 over the members' rests: the longest. A group rests once a round for it, in
    /// the workout, in the time estimate and on the Day editor's row. No rests falls back to the default.
    public static func groupRest(of rests: [RestDuration]) -> RestDuration {
        rests.max() ?? .defaultRest
    }

    /// Rule 44 member letters: 0 → "A" … 4 → "E", continuing through "Z"; beyond that the
    /// 1-based position as digits.
    public static func letter(forMemberAt position: Int) -> String {
        guard (0 ..< 26).contains(position), let scalar = Unicode.Scalar(UInt32(65 + position)) else {
            return String(position + 1)
        }
        return String(Character(scalar))
    }

    // MARK: - Internal

    /// Groups indices 0..<flags.count, where `flags[i]` means "joins the previous group".
    static func groups(joiningPrevious flags: [Bool]) -> [[Int]] {
        var groups: [[Int]] = []
        for (index, joins) in flags.enumerated() {
            if joins, index > 0 {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups
    }

    private static func members(of block: Block, in exercises: [WorkoutExercise]) -> [WorkoutExercise] {
        block.exerciseIndices.filter(exercises.indices.contains).map { exercises[$0] }
    }

    /// The rows of a block split into rounds: working rounds first, then drop rounds.
    private static func rounds(block: Block, exercises: [WorkoutExercise]) -> [[SetRef]] {
        let members = block.exerciseIndices.filter(exercises.indices.contains)
        let rows = members.map { exerciseIndex in
            let sets = exercises[exerciseIndex].sets.enumerated()
            let ref = { SetRef(exerciseIndex: exerciseIndex, setIndex: $0) }
            return (
                regular: sets.filter { $0.element.kind != .drop }.map { ref($0.offset) },
                drop: sets.filter { $0.element.kind == .drop }.map { ref($0.offset) }
            )
        }
        return interleave(rows.map(\.regular)) + interleave(rows.map(\.drop))
    }

    /// Round `r` holds the `r`-th element of every column that has one, in column order.
    private static func interleave(_ columns: [[SetRef]]) -> [[SetRef]] {
        let depth = columns.map(\.count).max() ?? 0
        return (0 ..< depth).map { round in
            columns.compactMap { round < $0.count ? $0[round] : nil }
        }
    }
}
