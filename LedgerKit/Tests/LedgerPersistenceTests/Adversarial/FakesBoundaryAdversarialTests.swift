import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F07 S1 adversarial round 1: single calls at the storage boundary, each made on a fresh GRDB stack and on fresh
/// `InMemoryStores`, which must answer alike: the same error or none, and the same value read back. Each case is
/// one value a later feature could hand a store (a converted weight, a date from a broken clock, an unsorted
/// inventory, a program saved before the catalog is seeded). The failing cases are findings F7-1 to F7-4
/// (`tasks/features/F07-composition-di/test-findings.md`).
@Suite("Adversarial F07 S1 · fakes at the storage boundary", .tags(.persistence))
struct FakesBoundaryAdversarialTests {
    typealias Kit = BoundaryKit

    static func outcome(_ stores: Kit.Stores, _ probe: Kit.Probe) async -> String {
        do {
            return try await "ok, then \(probe.run(stores))"
        } catch {
            return "threw \(error)"
        }
    }

    static func check(_ probe: Kit.Probe) async throws {
        let stored = try await outcome(Kit.grdb(), probe)
        let faked = try await outcome(Kit.fakes(), probe)
        #expect(stored == faked, "GRDB: \(stored)\nfake: \(faked)")
    }

    @Test("F7-1: a weight that is no whole number of 10⁻⁷ g, or a date that is not finite", arguments: Kit.exactness)
    func exactness_fakeAnswersAsGRDB(_ probe: Kit.Probe) async throws {
        try await Self.check(probe)
    }

    @Test("F7-2: settings and envelopes as their encoding stores them", arguments: Kit.encoding)
    func encoding_fakeAnswersAsGRDB(_ probe: Kit.Probe) async throws {
        try await Self.check(probe)
    }

    @Test("F7-3: a program saved before its exercises are", arguments: Kit.foreignKeys)
    func foreignKeys_fakeAnswersAsGRDB(_ probe: Kit.Probe) async throws {
        try await Self.check(probe)
    }

    @Test("F7-4: which error a workout with two faults throws", arguments: Kit.precedence)
    func precedence_fakeAnswersAsGRDB(_ probe: Kit.Probe) async throws {
        try await Self.check(probe)
    }

    @Test(
        "Deleted programs and workouts, and ids another workout holds: the fake answers as GRDB does",
        arguments: Kit.held
    )
    func held_fakeAnswersAsGRDB(_ probe: Kit.Probe) async throws {
        try await Self.check(probe)
    }
}

/// The stores and probes of `FakesBoundaryAdversarialTests`.
enum BoundaryKit {
    struct Stores: Sendable {
        let exercises: any ExerciseRepository
        let programs: any ProgramRepository
        let workouts: any WorkoutRepository
        let settings: any SettingsRepository
        let events: any WorkoutEventStore
    }

    struct Probe: Sendable, CustomTestStringConvertible {
        let name: String
        /// Makes the call(s) and returns what the lifter would see afterwards.
        let run: @Sendable (Stores) async throws -> String

        init(_ name: String, _ run: @escaping @Sendable (Stores) async throws -> String) {
            self.name = name
            self.run = run
        }

        var testDescription: String {
            name
        }
    }

    /// GRDB over one in-memory database, `S2Kit.slotExercises` saved (as the S3 stack does).
    static func grdb() async throws -> Stores {
        let stack = try await S3Kit.stack()
        return Stores(
            exercises: stack.exercises,
            programs: stack.programs,
            workouts: stack.workouts,
            settings: GRDBSettingsRepository(stack.queue),
            events: GRDBWorkoutEventStore(stack.queue)
        )
    }

    /// The fakes, with `S2Kit.slotExercises` saved the same way.
    static func fakes() async throws -> Stores {
        let stores = InMemoryStores()
        for exercise in S2Kit.slotExercises {
            try await stores.exercises.save(exercise)
        }
        return Stores(
            exercises: stores.exercises,
            programs: stores.programs,
            workouts: stores.workouts,
            settings: stores.settings,
            events: stores.events
        )
    }

    static let eighthPound = Weight.pounds(0.125)
    static let infinite = Date(timeIntervalSinceReferenceDate: .infinity)

    static func workout(_ change: (inout WorkoutState) -> Void = { _ in }) -> WorkoutState {
        var workout = S3Kit.workout(1, [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5), S3Kit.set(100, 5)])])
        change(&workout)
        return workout
    }

    static func materialized(_ workout: WorkoutState) -> @Sendable (Stores) async throws -> String {
        { stores in
            try await stores.workouts.materialize(workout, slotUpdates: [])
            return try await "\(stores.workouts.recent(limit: 5).count) stored"
        }
    }

    static func program(_ change: (inout Program) throws -> Void = { _ in }) throws -> Program {
        var program = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 2)
        try change(&program)
        return program
    }

    static func savedProgram(_ given: Program?) -> @Sendable (Stores) async throws -> String {
        { stores in
            let program = try #require(given)
            try await stores.programs.save(program)
            return try await "active: \(stores.programs.active()?.name ?? "none")"
        }
    }
}

// MARK: - Probes

extension BoundaryKit {
    /// ADR-007's exact weights and the date columns (F7-1).
    static let exactness: [Probe] = [
        Probe("a workout set of ⅛ lb", materialized(workout { $0.exercises[0].sets[0].weight = eighthPound })),
        Probe("a workout target load of ⅛ lb", materialized(workout { $0.exercises[0].targetLoad = eighthPound })),
        Probe("a 10⁹ kg set, beyond the column", materialized(workout {
            $0.exercises[0].sets[0].weight = .kilograms(1_000_000_000)
        })),
        Probe("a workout that started at +∞", materialized(workout { $0.startedAt = infinite })),
        Probe("a workout that ended at +∞", materialized(workout { $0.endedAt = infinite })),
        Probe("a set done at +∞", materialized(workout { $0.exercises[0].sets[0].doneAt = infinite })),
        Probe("updateSets with a ⅛ lb set") { stores in
            try await stores.workouts.materialize(workout(), slotUpdates: [])
            var sets = workout().exercises[0].sets
            sets[0].weight = eighthPound
            try await stores.workouts.updateSets(workoutExerciseID: S3Kit.rowID(1, 0), sets: sets)
            return "updated"
        },
        Probe("a slot whose start load is ⅛ lb", savedProgram(try? program { program in
            program.days[0].slots[0] = try program.days[0].slots[0].with(startLoad: eighthPound)
        })),
        Probe("a custom exercise whose start load is ⅛ lb") { stores in
            try await stores.exercises.save(S2Kit.exercise(20, "Odd", loads: [.lb: eighthPound]))
            return try await "\(stores.exercises.all().count) exercises"
        },
        Probe("a catalog entry whose start load is ⅛ lb") { stores in
            try await stores.exercises.seedIfNeeded([S2Kit.exercise(21, "Odd", loads: [.lb: eighthPound])], version: 1)
            return try await "\(stores.exercises.all().count) exercises"
        }
    ]

    /// Values whose stored encoding differs from the value given (F7-2).
    static let encoding: [Probe] = [
        Probe("settings whose plates are unsorted, repeated and zero") { stores in
            var settings = Settings.default
            settings.plateInventory[.lb]?.plates = [.pounds(5), .pounds(45), .pounds(5), .zero]
            try await stores.settings.save(settings)
            return try await "plates \(stores.settings.load().plateInventory[.lb]?.plates.map(\.pounds) ?? [])"
        },
        Probe("settings with a NaN bar") { stores in
            var settings = Settings.default
            settings.plateInventory[.kg] = PlateInventory(bar: Weight(grams: .nan), plates: [])
            try await stores.settings.save(settings)
            return "saved"
        },
        Probe("an envelope logging a NaN weight") { stores in
            let event = WorkoutEvent.setLogged(
                exerciseIndex: 0,
                setID: EventBuilders.setID(0, 0),
                weight: Weight(grams: .nan),
                reps: Reps(clamping: 5),
                doneAt: EventBuilders.start
            )
            let envelope = EventBuilders.envelope(event, seq: 1, at: EventBuilders.start)
            return try await "\(stores.events.append([envelope]).count) appended"
        }
    ]

    /// A slot naming an exercise the store lacks (F7-3).
    static let foreignKeys: [Probe] = [
        Probe("a program whose slot names an exercise that is not stored", savedProgram(try? program { program in
            program.days[0].slots[0] = try program.days[0].slots[0].with(exercise: S2Kit.exerciseID(99))
        }))
    ]

    /// Two faults in one workout (F7-4).
    static let precedence: [Probe] = [
        Probe("a workout named with U+0000 that repeats a set id", materialized(workout {
            $0.name = "Push\u{0}"
            $0.exercises[0].sets[1] = $0.exercises[0].sets[0]
        })),
        Probe("an exercise named with U+0000 in a workout that repeats a set id", materialized(workout {
            $0.exercises[0].name = "Bench\u{0}"
            $0.exercises[0].sets[1] = $0.exercises[0].sets[0]
        }))
    ]

    /// What held: deleted rows and ids other rows hold.
    static let held: [Probe] = [
        Probe("slot updates naming a slot of a deleted program") { stores in
            let program = try program()
            try await stores.programs.save(program)
            try await stores.programs.delete(program.id)
            let slot = try program.days[0].slots[0].with(misses: [0, 1])
            try await stores.workouts.materialize(workout(), slotUpdates: [slot])
            try await stores.programs.save(program)
            return try await "misses after revival: \(stores.programs.active()?.days[0].slots[0].misses.sorted() ?? [])"
        },
        Probe("updateSets on an exercise of a deleted workout") { stores in
            try await stores.workouts.materialize(workout(), slotUpdates: [])
            try await stores.workouts.delete(id: S3Kit.workoutID(1))
            try await stores.workouts.updateSets(workoutExerciseID: S3Kit.rowID(1, 0), sets: [])
            return "updated"
        },
        Probe("updateSets with a set id another workout holds") { stores in
            try await stores.workouts.materialize(workout(), slotUpdates: [])
            let second = S3Kit.workout(2, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(100, 5)])])
            try await stores.workouts.materialize(second, slotUpdates: [])
            try await stores.workouts.updateSets(
                workoutExerciseID: S3Kit.rowID(2, 0),
                sets: workout().exercises[0].sets
            )
            return "updated"
        }
    ]
}
