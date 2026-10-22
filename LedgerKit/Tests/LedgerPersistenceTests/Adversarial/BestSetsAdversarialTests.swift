import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F12 S1 adversarial round 1 (G2), N3: `bestSets()` is `bestSet(exerciseID:)` of every exercise, in one read.
/// The contract clause pins one hand-made history; F05's random scripts (`HistoryScript`: edits, deletes,
/// refused writes, zero loads, kg beside lb, every kind of set, sets left undone) never asked `bestSets`, because
/// it did not exist when they were written. Here they do, on GRDB, on `HistoryModel` and on LedgerFakes'
/// in-memory stores, after every step. The other tests take the edges one at a time.
@Suite("Adversarial F12 S1 · bestSets", .tags(.persistence, .property), .timeLimit(.minutes(5)))
struct BestSetsAdversarialTests {
    typealias History = HistoryModelAdversarialTests

    static let seeds = Array(PropertySeed.all.prefix(60))

    /// `bestSet(exerciseID:)` of each of the script's exercises, as `bestSets()` spells an entry; one with none
    /// has no key.
    static func oneByOne(_ stats: any StatsQueries) async throws -> [ExerciseID: BestSet] {
        var bests: [ExerciseID: BestSet] = [:]
        for exercise in HistoryScript.exercises {
            if let best = try await stats.bestSet(exerciseID: exercise) {
                bests[exercise] = BestSet(weight: best.weight, reps: best.reps)
            }
        }
        return bests
    }

    /// The seed's script on GRDB, the model and the fakes: the first step at which a `bestSets()` differs from
    /// GRDB's, or GRDB's from its own `bestSet(exerciseID:)`; `nil` when none does.
    static func firstMismatch(_ seed: PropertySeed) async throws -> String? {
        var script = HistoryScript(seed: seed)
        let stack = try await S3Kit.stack()
        let stats = stack.stats(now: script.now)
        let model = HistoryModel(now: script.now)
        let now = script.now
        let fakes = InMemoryStores(now: { now })
        for step in 0 ..< 14 {
            let operation = script.next()
            stack.clock.advance()
            _ = await History.apply(operation, to: stack.workouts)
            _ = await History.apply(operation, to: model)
            _ = await History.apply(operation, to: fakes.workouts)
            let stored = try await stats.bestSets()
            let single = try await oneByOne(stats)
            let modelled = try await model.bestSets()
            let faked = try await fakes.stats.bestSets()
            if stored != single {
                return "step \(step), \(operation): bestSets \(stored), bestSet one by one \(single)"
            }
            if stored != modelled {
                return "step \(step), \(operation): GRDB \(stored), model \(modelled)"
            }
            if stored != faked {
                return "step \(step), \(operation): GRDB \(stored), fakes \(faked)"
            }
        }
        return nil
    }

    @Test(
        "Random histories: bestSets is bestSet of every exercise, on GRDB, the model and the fakes",
        arguments: seeds
    )
    func randomHistory_bestSets_isBestSetOfEveryExercise(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstMismatch(seed)
        #expect(mismatch == nil, "\(seed)")
    }

    /// GRDB and the in-memory stores, the two the app and the features are tested over, each with the same
    /// workouts stored.
    static func bothStores(_ workouts: [WorkoutState]) async throws -> [(String, any StatsQueries)] {
        let stack = try await S3Kit.stack()
        let fakes = InMemoryStores(now: { S3Kit.now })
        for workout in workouts {
            try await stack.materialize(workout)
            try await fakes.workouts.materialize(workout, slotUpdates: [])
        }
        return [("GRDB", stack.stats()), ("in memory", fakes.stats)]
    }

    @Test("One weight entered in kg and in lb is one weight: of the two, the set with more reps is the best")
    func bestSets_sameWeightInKgAndLb_tieGoesToMoreReps() async throws {
        // 100 lb is exactly 45.359237 kg (ADR-007's exact weights): the two sets tie on weight.
        let workout = S3Kit.workout(1, [S3Kit.RowSpec(S3Kit.bench, [
            S3Kit.SetSpec(weight: .pounds(100), reps: 5),
            S3Kit.SetSpec(weight: .kilograms(Decimal(string: "45.359237") ?? 0), reps: 6),
            S3Kit.SetSpec(weight: .kilograms(45), reps: 12)
        ])])
        for (name, stats) in try await Self.bothStores([workout]) {
            let best = try #require(try await stats.bestSets()[S3Kit.bench], "\(name)")
            #expect(best.reps == Reps(clamping: 6), "\(name)")
            #expect(best.weight == .pounds(100), "\(name)")
        }
    }

    @Test("A bodyweight exercise logged at no load has a best: the zero load, with its most reps")
    func bestSets_zeroLoadOnly_isAnEntryWithMostReps() async throws {
        let workout = S3Kit.workout(1, [S3Kit.RowSpec(S3Kit.press, [
            S3Kit.SetSpec(weight: .zero, reps: 8),
            S3Kit.SetSpec(weight: .zero, reps: 12),
            S3Kit.SetSpec(weight: .zero, reps: 20, kind: .warmup)
        ])])
        for (name, stats) in try await Self.bothStores([workout]) {
            #expect(
                try await stats.bestSets()[S3Kit.press] == BestSet(weight: .zero, reps: Reps(clamping: 12)),
                "\(name)"
            )
        }
    }

    @Test("One exercise on two rows of one workout: the best of both rows, and one entry")
    func bestSets_exerciseOnTwoRows_isTheBestOfBoth() async throws {
        let workout = S3Kit.workout(1, [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(185, 5)]),
            S3Kit.RowSpec(S3Kit.row, [S3Kit.set(135, 8)]),
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(195, 3), S3Kit.set(225, 1, .drop)])
        ])
        for (name, stats) in try await Self.bothStores([workout]) {
            let bests = try await stats.bestSets()
            #expect(bests.count == 2, "\(name)")
            #expect(bests[S3Kit.bench] == BestSet(weight: .pounds(195), reps: Reps(clamping: 3)), "\(name)")
        }
    }

    @Test("A set edited away (updateSets) takes its best with it; the next one counts")
    func bestSets_heaviestSetEditedAway_fallsToTheNext() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.workout(1, [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(225, 1), S3Kit.set(185, 5)])])
        try await stack.materialize(workout)
        #expect(try await stack.stats().bestSets()[S3Kit.bench]?.weight == .pounds(225))
        let row = workout.exercises[0]
        try await stack.workouts.updateSets(workoutExerciseID: row.id, sets: Array(row.sets.suffix(1)))
        #expect(try await stack.stats().bestSets()[S3Kit.bench] == BestSet(
            weight: .pounds(185),
            reps: Reps(clamping: 5)
        ))
        try await stack.workouts.delete(id: workout.id)
        #expect(try await stack.stats().bestSets().isEmpty)
    }

    /// F12-S1-4 (low): a set whose weight cannot be read is "left out" by taking its exercise's whole entry with
    /// it, since only the first of each exercise's ranking is read. SQLite orders a text above every integer, so
    /// a damaged weight on even a light set ranks first and hides the real best. `bestSet(exerciseID:)` throws for
    /// that exercise, so the history (S2) will fail where the Library shows "—". Every other exercise keeps its
    /// best, which is what the implementation promises; this pins both halves.
    @Test("A damaged weight leaves out its exercise's entry, and only that exercise's")
    func bestSets_damagedWeight_leavesOutOnlyItsExercise() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.workout(1, [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(225, 3), S3Kit.set(45, 10)]),
            S3Kit.RowSpec(S3Kit.row, [S3Kit.set(135, 8)])
        ])
        try await stack.materialize(workout)
        let light = ColumnCodec.text(workout.exercises[0].sets[1].id)
        try await stack.damage("UPDATE logged_set SET weight_e7g = 'heavy' WHERE id = ?", [light])
        let bests = try await stack.stats().bestSets()
        #expect(bests[S3Kit.row] == BestSet(weight: .pounds(135), reps: Reps(clamping: 8)))
        #expect(bests[S3Kit.bench] == nil, "the damaged light set ranks first and its exercise has no entry")
    }
}
