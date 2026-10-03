import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 records follow-up (product decision #27), adversarial round 1: the invariant against `RecordOracle`, which
/// shares no code with the store's replay. Random histories of few lifts, few weights and few starts, so ties,
/// late workouts, moved starts, deloads, swapped and dropped exercises and revivals are common.
@Suite("Adversarial records · the invariant against an oracle", .tags(.persistence, .property), .timeLimit(.minutes(5)))
struct RecordReplayAdversarialTests {
    static let seeds = TestLane.runsSlowTests ? PropertySeed.all : Array(PropertySeed.all.prefix(60))
    static let lifts = [S3Kit.bench, S3Kit.squat, S3Kit.row]

    /// One script's state: the operations' generator, and the live workouts the store should hold.
    struct Script {
        var rng: SeededGenerator
        var live: [Int: WorkoutState] = [:]

        mutating func pick<Value>(_ values: [Value]) -> Value {
            values[Int.random(in: 0 ..< values.count, using: &rng)]
        }

        mutating func sets() -> [S3Kit.SetSpec] {
            (0 ..< Int.random(in: 0 ... 3, using: &rng)).map { _ in
                S3Kit.SetSpec(
                    weight: pick([.pounds(100), .pounds(105), .pounds(110), .pounds(105), .zero, Weight(e7g: 1)]),
                    reps: pick([1, 3, 5, 5, 12, 13]),
                    kind: pick([.working, .working, .added, .drop, .warmup]),
                    isDone: Int.random(in: 0 ..< 10, using: &rng) != 0
                )
            }
        }

        mutating func workout(_ number: Int) -> WorkoutState {
            let rows = (0 ..< Int.random(in: 1 ... 3, using: &rng)).map { _ in S3Kit.RowSpec(pick(lifts), sets()) }
            let start = S3Kit.day(Double(pick([-9, -5, -5, -2, 0, 0, 3])))
            var workout = S3Kit.workout(number, endedAt: start.addingTimeInterval(1800), minutes: 30, rows)
            workout.isDeload = Int.random(in: 0 ..< 6, using: &rng) == 0
            return workout
        }
    }

    enum Step {
        case materialize(Int, WorkoutState)
        case edit(Int, Int, [LoggedSet])
        case delete(Int)
    }

    static func next(_ script: inout Script) -> Step {
        let number = Int.random(in: 1 ... 7, using: &script.rng)
        switch Int.random(in: 0 ..< 10, using: &script.rng) {
        case 0 ..< 5:
            return .materialize(number, script.workout(number))
        case 5 ..< 8:
            let row = Int.random(in: 0 ... 2, using: &script.rng)
            let spec = S3Kit.RowSpec(S3Kit.bench, script.sets())
            let sets = S3Kit.exercise(number, row, spec, doneAt: S3Kit.now).sets
            return .edit(number, row, sets)
        default:
            return .delete(number)
        }
    }

    /// Applies `step` to the store and to the script's live workouts; `nil` when both agree on the outcome.
    static func apply(_ step: Step, to stack: S3Kit.Stack, _ script: inout Script) async throws -> String? {
        switch step {
        case let .materialize(number, workout):
            try await stack.materialize(workout)
            script.live[number] = workout
        case let .edit(number, row, sets):
            let id = S3Kit.rowID(number, row)
            guard var workout = script.live[number], let index = workout.exercises.firstIndex(where: { $0.id == id })
            else {
                await #expect(throws: LedgerPersistenceError.missingRow("workout_exercise \(id.rawValue.uuidString)")) {
                    try await stack.workouts.updateSets(workoutExerciseID: id, sets: sets)
                }
                return nil
            }
            workout.exercises[index].sets = sets
            try await stack.workouts.updateSets(workoutExerciseID: id, sets: sets)
            script.live[number] = workout
        case let .delete(number):
            try await stack.workouts.delete(id: S3Kit.workoutID(number))
            script.live[number] = nil
        }
        return nil
    }

    /// What the store holds against the oracle: every lift's records, every live workout's `pr_count`, and the
    /// bests before every live workout and before three that are not stored.
    static func mismatch(_ stack: S3Kit.Stack, _ live: [WorkoutState]) async throws -> String? {
        let records = RecordOracle.replay(live)
        let stats = stack.stats()
        for lift in lifts {
            let stored = try await stats.personalRecords(exerciseID: lift)
            let expected = RecordOracle.list(records, of: lift)
            if stored != expected {
                return "records of \(lift): got \(stored), expected \(expected)"
            }
        }
        let counts = try await stack
            .texts("SELECT id || ' ' || pr_count FROM workout WHERE deleted_at IS NULL ORDER BY id")
        let expectedCounts = live.map { "\($0.id.rawValue.uuidString) \(records[$0.id]?.count ?? 0)" }.sorted()
        if counts != expectedCounts {
            return "pr_count: got \(counts), expected \(expectedCounts)"
        }
        let probes = [-5.0, 0, 9].flatMap { day in
            [0, 99].map { S3Kit.workout($0, endedAt: S3Kit.day(day).addingTimeInterval(1800), minutes: 30, []) }
        }
        for place in live + probes {
            let bests = try await stats.bests(before: place, for: Set(lifts))
            let history = RecordOracle.bests(before: place, of: live)
            let expected = lifts.reduce(into: [ExerciseID: RecordOracle.History]()) { result, lift in
                let estimate = bests.e1RM[lift]
                let weights = (bests.weightAtReps[lift] ?? [:])
                    .reduce(into: [Int: Weight]()) { $0[$1.key.value] = $1.value }
                if estimate != nil || !weights.isEmpty {
                    result[lift] = RecordOracle.History(estimate: estimate, atReps: weights)
                }
            }
            if expected != history {
                return "bests before \(place.id): got \(expected), expected \(history)"
            }
        }
        return nil
    }

    @Test("Random writes: records, record counts and bests always equal a replay from scratch", arguments: seeds)
    func randomHistory_matchesTheOracle(seed: PropertySeed) async throws {
        let stack = try await S3Kit.stack()
        var script = Script(rng: seed.generator)
        for step in 0 ..< 16 {
            stack.clock.advance()
            _ = try await Self.apply(Self.next(&script), to: stack, &script)
            let mismatch = try await Self.mismatch(stack, Array(script.live.values))
            try #require(mismatch == nil, "\(seed), step \(step): \(mismatch ?? "")")
        }
    }

    @Test("PersonalRecords.detect equals the oracle's set-by-set rule over random histories", arguments: seeds)
    func domainDetect_matchesTheOracle(seed: PropertySeed) {
        var script = Script(rng: seed.generator)
        let workouts = (1 ... 7).map { script.workout($0) }
        var bests = PersonalRecords.Bests()
        for workout in RecordOracle.ordered(workouts) {
            let history = RecordOracle.bests(before: workout, of: workouts)
            let expected = RecordOracle.detect(workout, over: history)
            #expect(
                PersonalRecords.detect(workout: workout, against: bests, now: workout.startedAt) == expected,
                "\(seed)"
            )
            bests.include(workout)
        }
    }
}
