import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8a adversarial round 1 (G2): criteria 1–3, `SwapAlternatives.ranked` and `replacement`, against
/// random catalogs and the shipped one. Expectations come from the plan and rulings Q1, Q3, Q9.
@Suite("Adversarial F10 S8a · alternatives and the replacement's numbers", .tags(.domain))
struct SwapAlternativesAdversarialTests {
    static func pick<T>(_ values: [T], _ rng: inout SeededGenerator) -> T {
        values[Int.random(in: 0 ..< values.count, using: &rng)]
    }

    static func exercise(_ number: Int, _ rng: inout SeededGenerator, ids: Int) -> Exercise {
        Exercise(
            id: ExerciseID(EventBuilders.uuid(0xC000 + number)),
            name: pick(["b", "A", "a", "Ä", "z", "1"], &rng) + "\(Int.random(in: 0 ..< 5, using: &rng))",
            shortName: "S",
            equipment: pick(Equipment.allCases, &rng),
            primaryMuscle: pick([.chest, .back], &rng),
            pattern: pick([.horizontalPush, .verticalPush], &rng),
            defaultStartLoad: [:],
            curatedAlternatives: (0 ..< Int.random(in: 0 ... 12, using: &rng)).map { _ in
                ExerciseID(EventBuilders.uuid(0xC000 + Int.random(in: 0 ..< ids + 3, using: &rng)))
            }
        )
    }

    /// The rules of criterion 1 that `ranked` breaks, from the plan alone.
    static func problems(
        _ ranked: [Exercise],
        for subject: Exercise,
        in catalog: [Exercise],
        excluding excluded: Set<ExerciseID>
    ) -> [String] {
        let ids = ranked.map(\.id)
        let held = Set(catalog.map(\.id))
        let allowed = { (id: ExerciseID) in held.contains(id) && id != subject.id && !excluded.contains(id) }
        var found: [String] = []
        let checks: [(Bool, String)] = [
            (ranked.count > 8, "more than 8"),
            (Set(ids).count != ids.count, "a duplicate"),
            (!ids.allSatisfy(allowed), "itself, an excluded one or one not in the catalog")
        ]
        found += checks.filter(\.0).map(\.1)
        // The curated prefix, in listed order, then only same pattern + muscle (Q3: no third tier).
        var curated: [ExerciseID] = []
        for id in subject.curatedAlternatives where allowed(id) && !curated.contains(id) {
            curated.append(id)
        }
        let prefix = Array(curated.prefix(8))
        if Array(ids.prefix(prefix.count)) != prefix {
            found.append("curated prefix out of order")
        }
        let isSimilar = { (candidate: Exercise) in
            candidate.pattern == subject.pattern && candidate.primaryMuscle == subject.primaryMuscle
        }
        if !ranked.dropFirst(prefix.count).allSatisfy(isSimilar) {
            found.append("a third-tier alternative")
        }
        let available = Set(catalog.filter { isSimilar($0) && allowed($0.id) }.map(\.id)).union(prefix)
        if ranked.count < min(8, available.count) {
            found.append("fewer than available")
        }
        return found
    }

    @Test(
        "Random catalogs: at most 8, unique, never itself or excluded, curated first, then pattern and muscle",
        arguments: PropertySeed.all
    )
    func ranked_randomCatalogs_keepTheRules(seed: PropertySeed) {
        var rng = seed.generator
        let count = Int.random(in: 0 ... 30, using: &rng)
        var catalog = (0 ..< count).map { Self.exercise($0, &rng, ids: count) }
        if !catalog.isEmpty, Bool.random(using: &rng) {
            catalog.append(catalog[0]) // a duplicate id
        }
        let subject = Bool.random(using: &rng) || catalog.isEmpty
            ? Self.exercise(count + 1, &rng, ids: count) : Self.pick(catalog, &rng)
        let excluded = Set(catalog.prefix(3).map(\.id).filter { _ in Bool.random(using: &rng) })
        let ranked = SwapAlternatives.ranked(for: subject, in: catalog, excluding: excluded)
        let problems = Self.problems(ranked, for: subject, in: catalog, excluding: excluded)
        #expect(problems.isEmpty, "\(seed): \(problems)")
        let again = SwapAlternatives.ranked(for: subject, in: catalog, excluding: excluded) == ranked
        #expect(again, "deterministic")
    }

    @Test("Shipped catalog: every exercise's list holds no other pattern, and nothing traps")
    func ranked_shippedCatalog_isOnePattern() throws {
        let catalog = try ExerciseCatalog.seed()
        for exercise in catalog {
            let ranked = SwapAlternatives.ranked(for: exercise, in: catalog)
            #expect(ranked.allSatisfy { $0.pattern == exercise.pattern }, "\(exercise.name)")
            #expect(ranked.count <= 8)
        }
    }

    static func current(_ equipment: Equipment, _ load: Weight) -> WorkoutExercise {
        var exercise = EventBuilders.seedSession().exercises[0]
        exercise.equipment = equipment
        exercise.targetLoad = load
        return exercise
    }

    static func named(_ name: String) throws -> Exercise {
        try #require(try ExerciseCatalog.seed().first { $0.name == name })
    }

    @Test("Q1: Bench 185 → Incline Bench never done 185; → Dumbbell Bench never done its start; last 60 → 60")
    func replacement_planExamples() throws {
        let bench = Self.current(.barbell, .pounds(185))
        let incline = try Self.named("Incline Bench Press")
        let dumbbell = try Self.named("Dumbbell Bench Press")
        #expect(SwapAlternatives.replacement(of: bench, with: incline, last: nil, units: .lb).load == .pounds(185))
        #expect(SwapAlternatives.replacement(of: bench, with: dumbbell, last: nil, units: .lb).load
            == dumbbell.startLoad(in: .lb))
        let last = LastPerformance(date: EventBuilders.start, sets: 3, reps: 8, load: .pounds(60))
        let withLast = SwapAlternatives.replacement(of: bench, with: dumbbell, last: last, units: .lb)
        #expect(withLast.load == .pounds(60) && withLast.lastPerformance == last && withLast.step == .pounds(2.5))
    }

    @Test("A pound history in a kilogram workout rounds to the kilogram step; a kettlebell steps 2 kg")
    func replacement_unitsAndKettlebell() throws {
        let bench = Self.current(.barbell, .kilograms(80))
        let incline = try Self.named("Incline Bench Press")
        let last = LastPerformance(date: EventBuilders.start, sets: 5, reps: 5, load: .pounds(185)) // 83.91 kg
        let swap = SwapAlternatives.replacement(of: bench, with: incline, last: last, units: .kg)
        #expect(swap.step == .kilograms(2.5) && swap.load == .kilograms(85))
        let bell = try Self.named("Kettlebell Floor Press")
        let bellSwap = SwapAlternatives.replacement(of: bench, with: bell, last: nil, units: .kg)
        #expect(bellSwap.step == .kilograms(2) && bellSwap.load == bell.startLoad(in: .kg))
        #expect(bellSwap.equipment == .kettlebell)
        // Same equipment, an off-step target: rounded to the step (Bench 81.6 kg → 82.5).
        let offStep = try Self.current(.barbell, .kilograms(#require(Decimal(string: "81.6"))))
        #expect(SwapAlternatives.replacement(of: offStep, with: incline, last: nil, units: .kg)
            .load == .kilograms(82.5))
    }

    @Test("Never below zero, never NaN: a negative or NaN history, a negative target; the result is well formed")
    func replacement_hostileInputs_areClamped() throws {
        let incline = try Self.named("Incline Bench Press")
        let inputs: [(WorkoutExercise, LastPerformance?)] = [
            (Self.current(.barbell, .pounds(-50)), nil),
            (
                Self.current(.barbell, .pounds(185)),
                LastPerformance(date: EventBuilders.start, sets: 1, reps: 1, load: .pounds(-200))
            ),
            (
                Self.current(.barbell, .pounds(185)),
                LastPerformance(date: EventBuilders.start, sets: 1, reps: 1, load: Weight(grams: .nan))
            ),
            (Self.current(.barbell, Weight(grams: .nan)), nil)
        ]
        for (number, input) in inputs.enumerated() {
            for units in Units.allCases {
                let swap = SwapAlternatives.replacement(of: input.0, with: incline, last: input.1, units: units)
                #expect(swap.load >= .zero && swap.load.grams.isFinite, "case \(number) \(units)")
                #expect(swap.step > .zero, "case \(number) \(units)")
            }
        }
    }
}
