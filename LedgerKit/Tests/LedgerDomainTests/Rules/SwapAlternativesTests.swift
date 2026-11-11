import Foundation
import LedgerDomain
import Testing

/// F10 S8 criteria 1 and 2: what a swap offers, best first, from any catalog.
@Suite("SwapAlternatives · ranked", .tags(.domain))
struct SwapAlternativesTests {
    static func exercise(
        _ number: UInt8,
        _ name: String,
        pattern: MovementPattern = .horizontalPush,
        muscle: MuscleGroup = .chest,
        curated: [UInt8] = []
    ) -> Exercise {
        Exercise(
            id: id(number),
            name: name,
            shortName: name.uppercased(),
            equipment: .barbell,
            primaryMuscle: muscle,
            pattern: pattern,
            defaultStartLoad: [:],
            curatedAlternatives: curated.map(id)
        )
    }

    static func id(_ number: UInt8) -> ExerciseID {
        ExerciseID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xA0, number)))
    }

    static func names(_ exercises: [Exercise]) -> [String] {
        exercises.map(\.name)
    }

    /// A press with two curated alternatives (one listed twice, one also a press), three more presses for the
    /// chest, a press for the shoulders, a row for the chest, and a squat.
    static let press = exercise(1, "Press", curated: [4, 2, 4])
    static let catalog: [Exercise] = [
        press,
        exercise(2, "Dip"),
        exercise(3, "Zercher Press"),
        exercise(4, "Floor Press", pattern: .squat, muscle: .quads), // curated, though nothing else alike
        exercise(5, "Cable Press"),
        exercise(6, "Arnold Press", muscle: .shoulders),
        exercise(7, "Chest Row", pattern: .horizontalPull),
        exercise(8, "Back Squat", pattern: .squat, muscle: .quads),
        exercise(9, "Bench Press")
    ]

    @Test("Curated first in their listed order, then pattern and muscle in name order; each once, never itself")
    func curatedThenSimilar_inOrder_deduped() {
        let ranked = SwapAlternatives.ranked(for: Self.press, in: Self.catalog)
        #expect(Self.names(ranked) == ["Floor Press", "Dip", "Bench Press", "Cable Press", "Zercher Press"])
    }

    @Test("An id in excluding is never offered, from either tier")
    func excluding_leavesOut() {
        let ranked = SwapAlternatives.ranked(for: Self.press, in: Self.catalog, excluding: [Self.id(4), Self.id(9)])
        #expect(Self.names(ranked) == ["Dip", "Cable Press", "Zercher Press"])
    }

    @Test("No more than eight, curated ones first")
    func atMostEight() {
        let many = (10 ... 30).map { Self.exercise(UInt8($0), "Press \($0)") }
        let curated = Self.exercise(1, "Press", curated: [30, 29])
        let ranked = SwapAlternatives.ranked(for: curated, in: [curated] + many)
        #expect(ranked.count == SwapAlternatives.limit)
        #expect(SwapAlternatives.limit == 8)
        #expect(Self.names(ranked) == ["Press 30", "Press 29"] + (10 ... 15).map { "Press \($0)" })
    }

    @Test("A custom exercise (no curated list) gets pattern and muscle only; a curated id not stored is skipped")
    func custom_andMissingCurated() {
        var custom = Self.exercise(40, "My Press")
        custom.isCustom = true
        #expect(Self.names(SwapAlternatives.ranked(for: custom, in: Self.catalog))
            == ["Bench Press", "Cable Press", "Dip", "Press", "Zercher Press"])
        let missing = Self.exercise(41, "Old Press", curated: [99, 2])
        #expect(Self.names(SwapAlternatives.ranked(for: missing, in: Self.catalog)).first == "Dip")
    }

    @Test("An empty catalog offers nothing; an exercise alone in its family offers its curated ones only")
    func emptyCatalog_andLoneExercise() {
        #expect(SwapAlternatives.ranked(for: Self.press, in: []).isEmpty)
        let squat = Self.exercise(8, "Back Squat", pattern: .squat, muscle: .quads)
        #expect(Self.names(SwapAlternatives.ranked(for: squat, in: Self.catalog)) == ["Floor Press"])
        let row = Self.exercise(7, "Chest Row", pattern: .horizontalPull)
        #expect(SwapAlternatives.ranked(for: row, in: Self.catalog).isEmpty)
    }

    @Test("A catalog holding one id twice offers it once, as its first copy")
    func repeatedID_offeredOnce() {
        let twin = Self.exercise(5, "Cable Press, again")
        let ranked = SwapAlternatives.ranked(for: Self.exercise(1, "Press"), in: Self.catalog + [twin])
        #expect(Self.names(ranked).filter { $0.hasPrefix("Cable Press") } == ["Cable Press"])
    }

    @Test("Barbell Bench Press on the shipped catalog: its four curated, then four presses for the chest")
    func shippedCatalog_bench() throws {
        let shipped = try ExerciseCatalog.seed()
        let bench = try #require(shipped.first { $0.name == "Barbell Bench Press" })
        let ranked = SwapAlternatives.ranked(for: bench, in: shipped)
        #expect(Self.names(ranked) == [
            "Dumbbell Bench Press", "Smith Machine Bench Press", "Weighted Dip", "Machine Chest Press",
            "Barbell Floor Press", "Cable Chest Press", "Decline Bench Press", "Decline Push-Up"
        ])
    }
}
