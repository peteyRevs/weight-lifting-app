import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S8b criteria 14, 15 and 19: the sheet's rows as the lifter sees them, property-style over seeded
/// workouts of the shipped catalog (and a history), checked against the contract's rules written out here
/// (criterion 1 of S8a, Q1, Q3, Q7, Q9), not against `SwapAlternatives`; and the plan's refusal of a stale
/// choice, case by case.
@MainActor
@Suite("Swap ranking and plan (adversarial)", .tags(.feature), .timeLimit(.minutes(4)))
struct WorkoutSwapRankingAdversarialTests {
    /// The equipment as the sheet words it (the contract's list).
    static let equipmentWords: [Equipment: String] = [
        .barbell: "Barbell", .dumbbell: "Dumbbell", .cable: "Cable", .machine: "Machine",
        .bodyweight: "Bodyweight", .kettlebell: "Kettlebell", .band: "Band"
    ]

    /// The contract's ranking, written out: curated (in the catalog) in order, then same pattern and primary
    /// muscle in name order; each once; never itself nor the workout's; at most 8.
    private static func ranking(
        of exercise: Exercise,
        in catalog: [Exercise],
        excluding: Set<ExerciseID>
    ) -> [Exercise] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }) { first, _ in first }
        let curated = exercise.curatedAlternatives.compactMap { byID[$0] }
        let similar = ExerciseSearch.sorted(catalog).filter {
            $0.pattern == exercise.pattern && $0.primaryMuscle == exercise.primaryMuscle
        }
        var taken = excluding.union([exercise.id])
        var out: [Exercise] = []
        for candidate in curated + similar where out.count < 8 && !taken.contains(candidate.id) {
            taken.insert(candidate.id)
            out.append(candidate)
        }
        return out
    }

    /// What the row says, from Q1 and Q7 written out.
    private static func detail(
        of candidate: Exercise,
        replacing current: WorkoutExercise,
        last: LastPerformance?,
        units: Units
    ) -> String {
        let step = candidate.equipment.defaultStep(in: units)
        let base = last?.load
            ?? (candidate.equipment == current.equipment ? current.targetLoad : candidate.startLoad(in: units))
        let load = max(base.rounded(toStep: step), .zero)
        let word = equipmentWords[candidate.equipment] ?? "?"
        guard load > .zero else {
            return word
        }
        return "\(word) · \(load.formatted(in: units)) \(units == .kg ? "kg" : "lb")"
    }

    @Test(
        "Seeded workouts: the rows keep the ranking, Q9, the cap, and say the load Use applies",
        arguments: RestSeeds.all
    )
    func rows_keepTheRules(seed: UInt64) async throws {
        var generator = SplitMix64(seed: seed)
        let catalog = try SwapG2Catalog.all()
        let names = Array(catalog.map(\.name).shuffled(using: &generator).prefix(5))
        let units: Units = Bool.random(using: &generator) ? .lb : .kg
        let workout = try SwapG2Catalog.workout(names, units: units)
        let history = Self.history(of: catalog, using: &generator)
        let bench = try await SwapG2Bench.make(workout) { stats in
            for (id, last) in history {
                await stats.set(last: last, for: id)
            }
        }
        defer { bench.following.cancel() }
        await bench.open()
        let sheet = try #require(bench.sheet)
        let shown = try #require(catalog.first { $0.id == workout.exercises[0].exerciseID })
        let expected = Self.ranking(
            of: shown, in: catalog, excluding: Set(workout.exercises.map(\.exerciseID))
        )
        let context = "seed \(seed), \(shown.name), \(units)"
        #expect(sheet.rows.map(\.id) == expected.map(\.id), "\(context): order")
        #expect(sheet.rows.count <= 8)
        #expect(Set(sheet.rows.map(\.id)).isDisjoint(with: workout.exercises.map(\.exerciseID)), "\(context): Q9")
        if expected.isEmpty {
            #expect(sheet.message == "No alternatives for this exercise.", "\(context)")
            #expect(sheet.toggle == nil)
        } else {
            #expect(sheet.toggle?.isOn == false, "\(context)")
        }
        for (row, candidate) in zip(sheet.rows, expected) {
            Self.check(row, candidate, workout: workout, last: history[candidate.id], context)
        }
        let reads = await bench.stats.lastCalls
        #expect(reads.count == expected.count, "\(context): one last-session read per row")
    }

    /// One row against what the contract says it shows and sends.
    private static func check(
        _ row: SwapSheetModel.Row,
        _ candidate: Exercise,
        workout: WorkoutState,
        last: LastPerformance?,
        _ context: String
    ) {
        let want = detail(of: candidate, replacing: workout.exercises[0], last: last, units: workout.units)
        #expect(row.detail == want, "\(context): \(candidate.name)")
        #expect(row.use == "Use")
        guard case let .swap(index, choice, alsoUpdateProgram) = row.choose else {
            Issue.record("\(context): a row sends a swap")
            return
        }
        #expect(index == 0 && !alsoUpdateProgram)
        #expect(choice.exerciseID == candidate.id && choice.name == candidate.name)
        #expect(choice.replacement.equipment == candidate.equipment)
        #expect(choice.replacement.lastPerformance == last)
    }

    /// A last session for about a third of `catalog`, at off-step and odd loads too: 0 to 400 lb in tenths.
    private static func history(
        of catalog: [Exercise],
        using generator: inout SplitMix64
    ) -> [ExerciseID: LastPerformance] {
        var history: [ExerciseID: LastPerformance] = [:]
        for exercise in catalog where Int.random(in: 0 ..< 3, using: &generator) == 0 {
            let tenths = Decimal(Int.random(in: 0 ... 4000, using: &generator)) / 10
            history[exercise.id] = LastPerformance(
                date: Fixtures.now.addingTimeInterval(-86400), sets: 3, reps: 8, load: .pounds(tenths)
            )
        }
        return history
    }
}
