import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1, criterion 3: "a failure injected mid-way leaves no rows". A trigger fails one
/// statement on each table in turn, on the last row a write reaches there, for a first materialisation, a
/// re-materialisation that changes and removes rows, a set edit and a delete. Every row and stamp of the
/// history tables and the misses must be as before, and the same call must then succeed.
@Suite("Adversarial S3 · atomic writes", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutAtomicityAdversarialTests {
    /// A statement that fails: `INSERT` or `UPDATE` on `table`.
    struct Failure: Sendable, CustomStringConvertible {
        let event: String
        let table: String

        var description: String {
            "\(event) ON \(table)"
        }

        static let inserts = S3Kit.historyTables.map { Failure(event: "INSERT", table: $0) }
        static let updates = S3Kit.historyTables.map { Failure(event: "UPDATE", table: $0) }
    }

    /// Installs a trigger that aborts `failure`'s statement, runs `body`, which must throw a `DatabaseError`,
    /// and removes the trigger; the rows must be as they were.
    static func expectNoChange(
        under failure: Failure,
        in stack: S3Kit.Stack,
        _ body: () async throws -> Void
    ) async throws {
        try await stack.execute("""
        CREATE TRIGGER injected BEFORE \(failure) BEGIN SELECT RAISE(ABORT, 'injected'); END
        """)
        stack.clock.advance()
        let before = try await stack.dump()
        await #expect(throws: DatabaseError.self, "\(failure) did not fail the call") { try await body() }
        #expect(try await stack.dump() == before, "rows changed although \(failure) failed")
        try await stack.execute("DROP TRIGGER injected")
    }

    /// A stored program, a workout from one of its slots, the two records it sets over `S3Kit.baseline` (stored
    /// first: records are detected, product decision #27), and the misses of two slots.
    struct Scenario {
        let stack: S3Kit.Stack
        let program: Program
        let workout: WorkoutState
        let records: [PersonalRecord]
        let slots: [Slot]

        init() async throws {
            stack = try await S3Kit.stack()
            program = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2)
            try await stack.programs.save(program)
            try await stack.materialize(S3Kit.baseline)
            workout = S3Kit.mixed(1)
            records = S3Kit.mixedRecords(of: workout)
            var first = program.days[0].slots[0]
            first.misses = [0, 1, 2]
            var second = program.days[1].slots[1]
            second.misses = []
            slots = [first, second]
        }

        func materialize(_ state: WorkoutState? = nil) async throws {
            try await stack.materialize(state ?? workout, slots: slots)
        }
    }

    @Test("A first materialisation that fails on any table's insert stores nothing", arguments: Failure.inserts)
    func failedFirstMaterialize_storesNothing(failure: Failure) async throws {
        let scenario = try await Scenario()
        try await Self.expectNoChange(under: failure, in: scenario.stack) { try await scenario.materialize() }
        #expect(try await scenario.stack.liveCounts() == S3Kit.expectedCounts([S3Kit.baseline]))
        #expect(try await scenario.stack.programs.active() == scenario.program)
        try await scenario.materialize()
        #expect(try await scenario.stack.workouts.workout(id: scenario.workout.id) == scenario.workout)
        let counts = S3Kit.expectedCounts([S3Kit.baseline, scenario.workout], records: 2)
        #expect(try await scenario.stack.liveCounts() == counts)
        #expect(try await scenario.stack.stats().personalRecords(exerciseID: S3Kit.bench) == scenario.records)
    }

    /// The second materialisation renames the workout, changes a row and a set, removes a row with its sets,
    /// changes a record (187.5 × 5 is the new best estimate), and writes other misses: an `UPDATE` on every
    /// table.
    @Test("A re-materialisation that fails on any table's update or insert changes nothing", arguments: Failure.updates)
    func failedRematerialize_changesNothing(failure: Failure) async throws {
        let scenario = try await Scenario()
        var first = scenario.program.days[0].slots[0]
        first.misses = [2]
        try await scenario.stack.materialize(scenario.workout, slots: [first])
        var edited = scenario.workout
        edited.name = "Session 1, rebuilt"
        edited.exercises[0].name = "Lift, renamed"
        edited.exercises[0].sets[1].weight = .pounds(187.5)
        edited.exercises.removeLast()
        try await Self.expectNoChange(under: failure, in: scenario.stack) {
            try await scenario.materialize(edited)
        }
        #expect(try await scenario.stack.workouts.workout(id: edited.id) == scenario.workout)
        try await scenario.materialize(edited)
        #expect(try await scenario.stack.workouts.workout(id: edited.id) == edited)
        #expect(try await scenario.stack.liveCounts() == S3Kit.expectedCounts([S3Kit.baseline, edited], records: 2))
    }

    @Test("A set edit that fails on the set, the workout row or a record changes nothing", arguments: [
        Failure(event: "INSERT", table: "logged_set"), Failure(event: "UPDATE", table: "logged_set"),
        Failure(event: "UPDATE", table: "workout"), Failure(event: "UPDATE", table: "personal_record")
    ])
    func failedUpdateSets_changesNothing(failure: Failure) async throws {
        let scenario = try await Scenario()
        try await scenario.materialize()
        let row = scenario.workout.exercises[0]
        var sets = Array(row.sets.dropFirst())
        sets[0].reps = Reps(clamping: 6)
        let added = SetID(S3Kit.uuid(0xC, 990))
        sets.append(LoggedSet(id: added, weight: .pounds(200), reps: .one, kind: .added, doneAt: S3Kit.now))
        try await Self.expectNoChange(under: failure, in: scenario.stack) {
            try await scenario.stack.workouts.updateSets(workoutExerciseID: row.id, sets: sets)
        }
        try await scenario.stack.workouts.updateSets(workoutExerciseID: row.id, sets: sets)
        #expect(try await scenario.stack.workouts.workout(id: scenario.workout.id)?.exercises[0].sets == sets)
    }

    @Test("A delete that fails on any of its four tables deletes nothing", arguments: Failure.updates.dropLast())
    func failedDelete_deletesNothing(failure: Failure) async throws {
        let scenario = try await Scenario()
        try await scenario.materialize()
        try await Self.expectNoChange(under: failure, in: scenario.stack) {
            try await scenario.stack.workouts.delete(id: scenario.workout.id)
        }
        #expect(try await scenario.stack.workouts.workout(id: scenario.workout.id) == scenario.workout)
        try await scenario.stack.workouts.delete(id: scenario.workout.id)
        #expect(try await scenario.stack.liveCounts() == S3Kit.expectedCounts([S3Kit.baseline]))
    }
}
