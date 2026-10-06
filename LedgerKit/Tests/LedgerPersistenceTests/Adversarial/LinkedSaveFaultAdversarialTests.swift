import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F10 S3 adversarial round 1, criterion 4 on the database: "when it fails, nothing changed: no history row, no
/// program change, the log whole". A trigger fails one statement of the save's transaction, on each table
/// the save writes and for each kind of statement; every row of every table must then be as it was, and the
/// same save must succeed once the trigger is gone.
@Suite("Adversarial F10 S3 · a failure at each statement of the save", .tags(.persistence), .timeLimit(.minutes(1)))
struct LinkedSaveFaultAdversarialTests {
    typealias Fixture = LinkedFixture

    /// The tables a save writes, and the statements a trigger can refuse on each.
    static let tables = [
        "workout",
        "workout_exercise",
        "logged_set",
        "personal_record",
        "slot_miss",
        "slot",
        "workout_event"
    ]
    static let statements = tables.flatMap { table in ["INSERT", "UPDATE", "DELETE"].map { "\($0) ON \(table)" } }

    /// Statements a first save with records, misses, a program change and a log to drop must run. It runs
    /// others too (it updates the workout's row and retires old misses), and a failure there is held to the
    /// same rule.
    static let firstSave: Set<String> = [
        "INSERT ON workout", "INSERT ON workout_exercise", "INSERT ON logged_set", "INSERT ON personal_record",
        "INSERT ON slot_miss", "UPDATE ON slot", "DELETE ON workout_event"
    ]

    /// A database holding an earlier workout (so the next one sets records), and the save under test: workout 1
    /// with misses for two slots, an update of a third and its log.
    struct Scene {
        let stores: LinkedStores
        let workout: WorkoutState
        let slots: [Slot]
        let expected: Program

        init() async throws {
            stores = try await LinkedStores.make(.database)
            try await stores.workouts.materialize(S3Kit.baseline, slotUpdates: [])
            let (swapped, first, second) = try (Fixture.slot(2), Fixture.slot(0), Fixture.slot(4))
            workout = Fixture.workout(1, updates: [swapped.id: Fixture.other(than: swapped)])
            slots = [Fixture.missing(first, [0, 1, 2]), Fixture.missing(second, [])]
            expected = try Fixture.program(1)
                .changing(swapped.id) { $0.exerciseID = Fixture.other(than: swapped) }
                .changing(first.id) { $0.misses = [0, 1, 2] }
                .changing(second.id) { $0.misses = [] }
            _ = try await stores.events.append(Fixture.log(of: workout, count: 5))
        }

        func save(_ state: WorkoutState? = nil) async -> String {
            await stores.save(state ?? workout, slots: slots, droppingLog: true)
        }

        func execute(_ sql: String) async throws {
            try await stores.queue?.write { try $0.execute(sql: sql) }
        }

        /// `nil` when the save is whole: the workout in history, the program changed, no event left.
        func wholeIssue() async throws -> String? {
            if let line = try await LinkedDifference.of(stores.program(1), expected, "program 1") {
                return line
            }
            guard try await stores.workouts.workout(id: workout.id) != nil else {
                return "the workout is not in history"
            }
            return try await stores.logCount(workout) == 0 ? nil : "events of the workout remain"
        }
    }

    /// Runs `save` with `statement` refused. Whether the save failed; when it did, nothing may have changed.
    static func refusing(_ statement: String, in scene: Scene, _ save: () async -> String) async throws -> Bool {
        try await scene
            .execute("CREATE TRIGGER injected BEFORE \(statement) BEGIN SELECT RAISE(ABORT, 'injected'); END")
        scene.stores.clock.advance()
        let before = try await scene.stores.dump()
        let outcome = await save()
        let after = try await scene.stores.dump()
        try await scene.execute("DROP TRIGGER injected")
        guard outcome != "true" else {
            return false
        }
        let rows = LinkedStores.difference(before, after)
        #expect(rows == nil, "\(statement) failed the save, and rows changed: \(rows ?? "")")
        #expect(outcome.contains("injected"), "\(statement): \(outcome.prefix(80))")
        return true
    }

    @Test(
        "A first save that fails at any statement changes no row of any table, and then succeeds",
        arguments: statements
    )
    func firstSave_failsAtAStatement_changesNothing(statement: String) async throws {
        let scene = try await Scene()
        let failed = try await Self.refusing(statement, in: scene) { await scene.save() }
        #expect(failed || !Self.firstSave.contains(statement), "\(statement) did not fail the save: is it still run?")
        if failed {
            #expect(try await scene.stores.logCount(scene.workout) == 5, "the log whole")
            #expect(try await scene.stores.workouts.workout(id: scene.workout.id) == nil, "no history row")
            #expect(await scene.save() == "true")
        }
        let issue = try await scene.wholeIssue()
        #expect(issue == nil, "\(statement): \(issue ?? "")")
    }

    @Test(
        "A save over an earlier one, with other sets and another update, that fails at any statement changes nothing",
        arguments: statements
    )
    func secondSave_failsAtAStatement_changesNothing(statement: String) async throws {
        let scene = try await Scene()
        #expect(await scene.stores.save(scene.workout, slots: scene.slots, droppingLog: false) == "false")
        var changed = scene.workout
        changed.exercises[0].sets[0].weight = .pounds(205)
        changed.exercises[1].sets.removeLast()
        let again = try Fixture.slot(5)
        changed.programUpdates[again.id] = Fixture.other(than: again)
        let failed = try await Self.refusing(statement, in: scene) { await scene.save(changed) }
        if failed {
            #expect(try await scene.stores.logCount(scene.workout) == 5, "the log whole")
            let kept = try await scene.stores.workouts.workout(id: scene.workout.id)?.exercises == scene.workout
                .exercises
            #expect(kept, "history still holds the first save")
        }
        #expect(await scene.save(changed) == "true")
        let isReplaced = try await scene.stores.workouts.workout(id: changed.id)?.exercises == changed.exercises
        #expect(isReplaced, "\(statement): the second save's rows are stored")
        #expect(try await scene.stores.logCount(scene.workout) == 0)
    }
}
