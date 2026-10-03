import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F07 S1 close-out: the fix round made the fakes check weights, dates, text, ids and slot exercises "in the
/// order the GRDB repository meets them" (F7-1, F7-3, F7-4). Here every value carries one to four faults drawn
/// at random, on GRDB and on `InMemoryStores` holding the same rows, and both must throw the same error (or
/// none) and keep the same state.
@Suite(
    "Adversarial F07 S1 close-out · faults in any combination",
    .tags(.persistence, .property),
    .timeLimit(.minutes(5))
)
struct FakesFaultOrderAdversarialTests {
    typealias History = HistoryModelAdversarialTests
    typealias WorkoutFault = @Sendable (inout WorkoutState) -> Void
    typealias ProgramFault = @Sendable (inout Program) throws -> Void

    static let seeds = Array(PropertySeed.all.prefix(100))
    static let eighth = Weight.pounds(0.125)
    static let infinite = Date(timeIntervalSinceReferenceDate: .infinity)

    /// Workout 2's ids, which workout 1 may take; every fault one a feature could send.
    static let workoutFaults: [WorkoutFault] = [
        { $0.exercises[0].sets[0].weight = eighth },
        { $0.exercises[1].sets[1].weight = eighth },
        { $0.exercises[0].targetLoad = eighth },
        { $0.exercises[1].step = eighth },
        { $0.startedAt = infinite },
        { $0.endedAt = infinite },
        { $0.exercises[1].sets[0].doneAt = infinite },
        { $0.name = "N\u{0}" },
        { $0.tag = "T\u{0}" },
        { $0.exercises[1].name = "E\u{0}" },
        { $0.exercises[1].sets[1] = $0.exercises[1].sets[0] },
        { $0.exercises[1] = $0.exercises[0] },
        { $0.exercises[1] = S3Kit.exercise(2, 0, S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(100, 5)]), doneAt: S3Kit.now) },
        { $0.exercises[0].sets[1] = S3Kit.exercise(
            2,
            0,
            S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(90, 5)]),
            doneAt: S3Kit.now
        ).sets[0] },
        { workout in
            // Each set fine alone (9 × 10¹⁵ units); the row's volume beyond the column (62 × 20 reps ≈ 1.1 × 10¹⁹).
            for index in workout.exercises[0].sets.indices {
                workout.exercises[0].sets[index].weight = .kilograms(900_000)
                workout.exercises[0].sets[index].reps = Reps(clamping: 20)
            }
            workout.exercises[0].sets += (0 ..< 60).map { position in
                LoggedSet(
                    id: S3Kit.setID(1, 5, position),
                    weight: .kilograms(900_000),
                    reps: Reps(clamping: 20),
                    kind: .working,
                    doneAt: S3Kit.now
                )
            }
        }
    ]

    static func workout(_ number: Int) -> WorkoutState {
        S3Kit.workout(number, endedAt: S3Kit.day(Double(-number)), [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5), S3Kit.set(105, 3)]),
            S3Kit.RowSpec(S3Kit.row, [S3Kit.set(80, 8), S3Kit.set(85, 6)])
        ])
    }

    @Test(
        "A workout with one to four random faults: the fake throws GRDB's error and keeps GRDB's history",
        arguments: seeds
    )
    func workoutFaults_matchGRDB(seed: PropertySeed) async throws {
        var random = seed.generator
        let stack = try await S3Kit.stack()
        let fakes = InMemoryStores()
        for store in [stack.workouts, fakes.workouts] as [any WorkoutRepository] {
            try await store.materialize(Self.workout(2), slotUpdates: [])
        }
        var spoiled = Self.workout(1)
        var picked: [Int] = []
        for _ in 0 ..< Int.random(in: 1 ... 4, using: &random) {
            let index = Int.random(in: 0 ..< Self.workoutFaults.count, using: &random)
            picked.append(index)
            Self.workoutFaults[index](&spoiled)
        }
        let sent = spoiled
        let stored = await History.outcome { try await stack.workouts.materialize(sent, slotUpdates: []) }
        let faked = await History.outcome { try await fakes.workouts.materialize(sent, slotUpdates: []) }
        #expect(stored == faked, "\(seed), faults \(picked)")
        #expect(try await stack.workouts.recent(limit: 10) == fakes.workouts.recent(limit: 10), "\(seed)")
    }

    /// Program 2 holds slot, day and week ids program 1 may take; exercise 99 is not stored.
    static let programFaults: [ProgramFault] = [
        { $0.days[0].slots[0] = try $0.days[0].slots[0].with(startLoad: eighth) },
        { $0.days[1].slots[1] = try $0.days[1].slots[1].with(step: eighth) },
        { $0.days[1].slots[0] = try $0.days[1].slots[0].with(exercise: S2Kit.exerciseID(99)) },
        { $0.days[0].slots[1] = try $0.days[0].slots[1].with(exercise: S2Kit.exerciseID(98)) },
        { $0 = try $0.rebuilt(name: "P\u{0}") },
        { $0.days[1].tag = "T\u{0}" },
        { $0.days[0].name = "D\u{0}" },
        { $0.days[1].slots[1] = $0.days[0].slots[0] },
        { program in
            let other = try S2Kit.program(2, weeks: 2, days: 2, slotsPerDay: 2, isActive: false)
            program.days[1].slots[0] = try Slot(
                id: other.days[0].slots[0].id, exerciseID: S2Kit.exerciseID(1), sets: 3, reps: 5, repsHi: 8,
                rpe: 8, restSeconds: 90, progression: .linear, startLoad: nil, step: nil,
                isSupersetWithPrevious: false, dropSets: 0, misses: []
            )
        }
    ]

    @Test(
        "A program with one to four random faults: the fake throws GRDB's error and keeps GRDB's program",
        arguments: seeds
    )
    func programFaults_matchGRDB(seed: PropertySeed) async throws {
        var random = seed.generator
        let stack = try await S3Kit.stack()
        let fakes = InMemoryStores()
        for exercise in S2Kit.slotExercises {
            try await fakes.exercises.save(exercise)
        }
        let other = try S2Kit.program(2, weeks: 2, days: 2, slotsPerDay: 2, isActive: false)
        let base = try S2Kit.program(1, weeks: 2, days: 2, slotsPerDay: 2)
        for store in [stack.programs, fakes.programs] as [any ProgramRepository] {
            try await store.save(other)
            try await store.save(base)
        }
        var spoiled = base
        var picked: [Int] = []
        for _ in 0 ..< Int.random(in: 1 ... 4, using: &random) {
            let index = Int.random(in: 0 ..< Self.programFaults.count, using: &random)
            picked.append(index)
            try Self.programFaults[index](&spoiled)
        }
        let sent = spoiled
        let stored = await History.outcome { try await stack.programs.save(sent) }
        let faked = await History.outcome { try await fakes.programs.save(sent) }
        #expect(stored == faked, "\(seed), faults \(picked)")
        #expect(try await stack.programs.active() == fakes.programs.active(), "\(seed)")
    }
}

extension FakesFaultOrderAdversarialTests {
    @Test(
        "An exercise with random faults in either load and either text: the fake throws GRDB's error",
        arguments: seeds
    )
    func exerciseFaults_matchGRDB(seed: PropertySeed) async throws {
        var random = seed.generator
        let stored = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        let fake = InMemoryExerciseRepository()
        let faults: [@Sendable (inout Exercise) -> Void] = [
            { $0.defaultStartLoad[.lb] = Self.eighth },
            { $0.defaultStartLoad[.kg] = Weight(grams: .nan) },
            { $0.name = "N\u{0}" },
            { $0.shortName = "S\u{0}" }
        ]
        var exercise = S2Kit.exercise(30, "Odd")
        for _ in 0 ..< Int.random(in: 1 ... 3, using: &random) {
            faults[Int.random(in: 0 ..< faults.count, using: &random)](&exercise)
        }
        let sent = exercise
        let seeding = Bool.random(using: &random)
        let action: @Sendable (any ExerciseRepository) async throws -> Void = { repository in
            if seeding {
                try await repository.seedIfNeeded([sent], version: 1)
            } else {
                try await repository.save(sent)
            }
        }
        let storedOutcome = await History.outcome { try await action(stored) }
        let fakeOutcome = await History.outcome { try await action(fake) }
        #expect(storedOutcome == fakeOutcome, "\(seed)")
        #expect(try await stored.all() == fake.all(), "\(seed)")
    }
}
