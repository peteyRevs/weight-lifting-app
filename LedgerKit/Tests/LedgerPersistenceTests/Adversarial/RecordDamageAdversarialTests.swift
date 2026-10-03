import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 records follow-up, close-out round: the orchestrator's decision on R-Q1 (a workout the replay cannot read is
/// skipped and logged) against `RecordOracle`, over random histories of one lift with damage injected. Damage is
/// seen when a write replays past it, so after every step an edit that changes nothing, of the earliest readable
/// workout, replays the whole lift. Then the readable workouts hold what the oracle replays over them, and a
/// damaged workout the records it held when it was damaged, until it is materialised again (the repair) or deleted.
@Suite(
    "Adversarial records close-out · damage against the oracle",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct RecordDamageAdversarialTests {
    static let seeds = TestLane.runsSlowTests ? PropertySeed.all : Array(PropertySeed.all.prefix(60))

    struct State {
        var live: [Int: WorkoutState] = [:]
        /// The damaged workouts, with the records they held when damaged.
        var damaged: [Int: [PersonalRecord]] = [:]

        var readable: [WorkoutState] {
            live.filter { damaged[$0.key] == nil }.map(\.value)
        }
    }

    static func workout(_ number: Int, _ rng: inout SeededGenerator) -> WorkoutState {
        let sets = (0 ..< Int.random(in: 1 ... 3, using: &rng)).map { _ in
            S3Kit.set(
                [100, 105, 110, 115][Int.random(in: 0 ..< 4, using: &rng)],
                [1, 5, 5, 8][Int.random(in: 0 ..< 4, using: &rng)],
                [.working, .working, .added, .warmup][Int.random(in: 0 ..< 4, using: &rng)]
            )
        }
        let start = S3Kit.day(Double([-8, -6, -6, -3, -1][Int.random(in: 0 ..< 5, using: &rng)]))
        var workout = S3Kit.workout(number, endedAt: start.addingTimeInterval(1800), minutes: 30, [
            S3Kit.RowSpec(S3Kit.bench, sets)
        ])
        workout.isDeload = Int.random(in: 0 ..< 8, using: &rng) == 0
        return workout
    }

    /// One random write, applied to the store and to `state`.
    static func step(_ stack: S3Kit.Stack, _ state: inout State, _ rng: inout SeededGenerator) async throws {
        let number = Int.random(in: 1 ... 6, using: &rng)
        switch Int.random(in: 0 ..< 10, using: &rng) {
        case 0 ..< 5:
            let workout = Self.workout(number, &rng)
            try await stack.materialize(workout)
            state.live[number] = workout
            state.damaged[number] = nil
        case 5 ..< 7:
            // Only a set that counts toward bests is read by the replay, so only its damage is seen.
            let counted = state.live[number].map { RecordOracle.counts($0.exercises[0].sets[0]) } ?? false
            if let workout = state.live[number], state.damaged[number] == nil, counted {
                let all = RecordOracle.replay(state.readable)
                state.damaged[number] = all[workout.id] ?? []
                try await stack.execute("UPDATE logged_set SET reps = 0 WHERE id = ?", [
                    workout.exercises[0].sets[0].id.rawValue.uuidString
                ])
            }
        case 7 ..< 9:
            if let workout = state.live[number], state.damaged[number] == nil {
                var sets = workout.exercises[0].sets
                sets[0].weight = .pounds([95, 120][Int.random(in: 0 ..< 2, using: &rng)])
                try await stack.workouts.updateSets(workoutExerciseID: workout.exercises[0].id, sets: sets)
                state.live[number]?.exercises[0].sets = sets
            }
        default:
            try await stack.workouts.delete(id: S3Kit.workoutID(number))
            state.live[number] = nil
            state.damaged[number] = nil
        }
    }

    /// An edit of the earliest readable workout that changes nothing: it replays the lift from there.
    static func replayAll(_ stack: S3Kit.Stack, _ state: State) async throws {
        guard let earliest = RecordOracle.ordered(state.readable).first else {
            return
        }
        try await stack.workouts.updateSets(
            workoutExerciseID: earliest.exercises[0].id,
            sets: earliest.exercises[0].sets
        )
    }

    static func mismatch(_ stack: S3Kit.Stack, _ state: State) async throws -> String? {
        try await replayAll(stack, state)
        var records = RecordOracle.replay(state.readable)
        for (number, held) in state.damaged {
            if let workout = state.live[number] {
                records[workout.id] = held
            }
        }
        let stored = try await stack.stats().personalRecords(exerciseID: S3Kit.bench)
        let expected = RecordOracle.list(records, of: S3Kit.bench)
        if stored != expected {
            return "records: got \(stored), expected \(expected)"
        }
        let counts = try await stack
            .texts("SELECT id || ' ' || pr_count FROM workout WHERE deleted_at IS NULL ORDER BY id")
        let expectedCounts = state.live.values.map { "\($0.id.rawValue.uuidString) \(records[$0.id]?.count ?? 0)" }
            .sorted()
        if counts != expectedCounts {
            return "pr_count: got \(counts), expected \(expectedCounts)"
        }
        for place in state.readable {
            let bests = try await stack.stats().bests(before: place, for: [S3Kit.bench])
            let history = RecordOracle.bests(before: place, of: state.readable)[S3Kit.bench]
            let weights = (bests.weightAtReps[S3Kit.bench] ?? [:])
                .reduce(into: [Int: Weight]()) { $0[$1.key.value] = $1.value }
            if history?.estimate != bests.e1RM[S3Kit.bench] || (history?.atReps ?? [:]) != weights {
                return "bests before \(place.id): got \(bests), expected \(String(describing: history))"
            }
        }
        return nil
    }

    @Test(
        "Random writes and damage: the readable history replays as the oracle says, the damaged keeps its records",
        arguments: seeds
    )
    func damage_isLeftOut_andRepaired(seed: PropertySeed) async throws {
        let stack = try await S3Kit.stack()
        var state = State()
        var rng = seed.generator
        for step in 0 ..< 18 {
            stack.clock.advance()
            try await Self.step(stack, &state, &rng)
            let mismatch = try await Self.mismatch(stack, state)
            try #require(mismatch == nil, "\(seed), step \(step): \(mismatch ?? "")")
        }
    }
}
