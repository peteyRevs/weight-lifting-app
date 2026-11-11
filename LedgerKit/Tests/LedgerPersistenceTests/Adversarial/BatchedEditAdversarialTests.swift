import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S3 adversarial (G2): `updateSets(_:of:)` on GRDB, read at the rows. One transaction and one replay, counted from
/// SQLite's own trace; every column of every row it should leave alone, compared whole; all or nothing when a write
/// fails halfway; and a fix that keeps the volume reaching every follower.
@Suite("Adversarial F13 S3 · the batched edit, at the rows", .tags(.persistence), .timeLimit(.minutes(2)))
struct BatchedEditAdversarialTests {
    private typealias Kit = BatchedEditKit

    // MARK: - One transaction, one replay

    @Test("One BEGIN, one COMMIT and one replay walk, however many exercises are named")
    func oneTransaction_oneReplay() async throws {
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        let map = Dictionary(uniqueKeysWithValues: middle.exercises.map { exercise in
            (exercise.id, Kit.raised(exercise.sets, to: .pounds(300)))
        })
        let sql = try await Kit.trace(stack) { try await stack.workouts.updateSets(map, of: middle.id) }
        let transactions = sql.filter { $0.hasPrefix("BEGIN") || $0.hasPrefix("COMMIT") || $0.hasPrefix("ROLLBACK") }
        #expect(transactions == ["BEGIN IMMEDIATE TRANSACTION", "COMMIT TRANSACTION"])
        let walks = sql.filter { $0.contains("MAX(logged_set.e1rm_e7g) AS e1rm_e7g") && $0.contains(">= (?, ?)") }
        #expect(walks.count == 1, "\(walks.count) replay walks")
        #expect(walks.first?.components(separatedBy: "?").count == 3 + 2 + 1, "the one walk names all three exercises")
        let storedReads = sql.filter { $0.contains("FROM personal_record JOIN workout") }
        #expect(storedReads.count == 1)
    }

    // MARK: - What it leaves alone

    @Test("Only the stepped set's columns move: every other row keeps every column, its stamp too")
    func untouchedRows_keepEveryColumn() async throws {
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        let before = try await Kit.all(in: stack)
        let (bench, squat) = (middle.exercises[0], middle.exercises[1])
        try await stack.workouts.updateSets(
            [
                bench.id: Kit.raised(bench.sets, to: .pounds(195)),
                squat.id: Kit.raised(squat.sets, to: .kilograms(105), reps: 6)
            ],
            of: middle.id
        )
        let after = try await Kit.all(in: stack)
        let touched = [ColumnCodec.text(bench.sets[0].id), ColumnCodec.text(squat.sets[0].id)]
        for (id, row) in after["logged_set"] ?? [:] {
            let moved = Kit.changed(before["logged_set"]?[id], row)
            if touched.contains(id) {
                #expect(moved.isSubset(of: ["weight_e7g", "reps", "e1rm_e7g", "updated_at"]), "\(moved)")
                #expect(moved.contains("updated_at"), "a synced row that changed takes a stamp")
            } else {
                #expect(moved.isEmpty, "set \(id): \(moved)")
            }
        }
        for (id, row) in after["workout_exercise"] ?? [:] {
            let moved = Kit.changed(before["workout_exercise"]?[id], row)
            #expect(moved.isEmpty, "exercise \(id): \(moved)")
        }
        for (id, row) in after["workout"] ?? [:] {
            let moved = Kit.changed(before["workout"]?[id], row)
            if id == ColumnCodec.text(middle.id) {
                let derived: Set = ["volume_e7g_reps", "pr_count", "updated_at"]
                #expect(moved.isSubset(of: derived), "the edited workout's \(moved)")
            } else {
                #expect(moved.isSubset(of: ["pr_count"]), "workout \(id): \(moved)")
            }
        }
        #expect(after["logged_set"]?.count == before["logged_set"]?.count, "no row added")
        let read = try #require(try await stack.workouts.workout(id: middle.id))
        #expect(read.exercises[0].sets[1] == bench.sets[1], "187.3 lb, exactly")
        #expect(read.exercises[1].sets[1] == squat.sets[1], "the set not logged")
        #expect(read.exercises[2] == middle.exercises[2])
    }

    @Test("Random steps in either unit read back as the same exact Decimal, and the totals are their exact sum")
    func steppedWeights_readBackExact() async throws {
        var random = SeededGenerator(seed: 0x0F13_0503)
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        var draft = middle
        for round in 0 ..< 40 {
            let original = draft
            let units: Units = round.isMultiple(of: 3) ? .kg : .lb
            for _ in 0 ..< 3 {
                let id = middle.exercises.flatMap(\.sets).randomElement(using: &random)?.id ?? SetID(UUID())
                let way: StepDirection = Bool.random(using: &random) ? .upward : .downward
                draft = SetEditing.stepping(id, .weight, way, in: draft, units: units)
            }
            try await stack.workouts.updateSets(SetEditing.changes(from: original, to: draft), of: middle.id)
            let read = try await stack.workouts.workout(id: middle.id)
            #expect(read == draft, "round \(round)")
            let entry = try await stack.workouts.historyEntries().first { $0.id == middle.id }
            #expect(entry?.volume == draft.volume, "round \(round)")
            #expect(entry?.doneSets == middle.doneSets)
            stack.clock.advance()
        }
    }
}

extension BatchedEditAdversarialTests {
    // MARK: - All or nothing

    @Test("A write that fails after the first exercise, or in the replay, leaves every row as it was")
    func failureHalfway_rollsBackAll() async throws {
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        let (bench, squat) = (middle.exercises[0], middle.exercises[1])
        let map = [
            bench.id: Kit.raised(bench.sets, to: .pounds(500)),
            squat.id: Kit.raised(squat.sets, to: .pounds(600))
        ]
        let before = try await Kit.all(in: stack)
        let oneSet = ColumnCodec.text(squat.sets[0].id)
        let triggers = [
            "BEFORE UPDATE ON logged_set WHEN new.id = '\(oneSet)' BEGIN SELECT RAISE(ABORT, 'a set'); END",
            "BEFORE INSERT ON personal_record BEGIN SELECT RAISE(ABORT, 'a record'); END",
            "BEFORE UPDATE ON personal_record BEGIN SELECT RAISE(ABORT, 'a record'); END"
        ]
        for trigger in triggers {
            try await stack.execute("CREATE TRIGGER fail_the_write \(trigger)")
            await #expect(throws: (any Error).self, "\(trigger)") {
                try await stack.workouts.updateSets(map, of: middle.id)
            }
            let after = try await Kit.all(in: stack)
            #expect(after == before, "after \(trigger)")
            try await stack.execute("DROP TRIGGER fail_the_write")
        }
        try await stack.workouts.updateSets(map, of: middle.id)
        #expect(try await stack.workouts.workout(id: middle.id)?.exercises[1].sets[0].weight == .pounds(600))
    }

    @Test("A set id another workout holds is refused, whichever way the map is walked, and nothing moves")
    func anotherWorkoutsSet_isRefused() async throws {
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        let before = try await Kit.all(in: stack)
        let (bench, squat) = (middle.exercises[0], middle.exercises[1])
        await #expect(throws: LedgerPersistenceError.self) {
            try await stack.workouts.updateSets(
                [bench.id: Kit.raised(bench.sets, to: .pounds(500)), squat.id: history.newer.exercises[0].sets],
                of: middle.id
            )
        }
        #expect(try await Kit.all(in: stack) == before)
    }

    @Test("A set id used twice in one call is refused, on GRDB and in memory, and nothing moves")
    func setUsedTwice_isRefused() async throws {
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        let before = try await Kit.all(in: stack)
        let memory = InMemoryStores(seed: InMemoryStores.Seed(workouts: history.all))
        let (bench, squat) = (middle.exercises[0], middle.exercises[1])
        let twice = [bench.id: bench.sets, squat.id: squat.sets + [bench.sets[0]]]
        let verdict = { (repository: any WorkoutRepository) async -> String in
            do {
                try await repository.updateSets(twice, of: middle.id)
                return "stored"
            } catch {
                return "\(error)"
            }
        }
        let onDisk = await verdict(stack.workouts)
        let inMemory = await verdict(memory.workouts)
        #expect(onDisk.contains("duplicateIdentifier"), "GRDB: \(onDisk)")
        #expect(inMemory.contains("duplicateIdentifier"), "in memory: \(inMemory)")
        #expect(try await Kit.all(in: stack) == before)
    }

    // MARK: - Who hears it

    /// C19. 200 × 5 and 250 × 4 are the same volume: a follower keyed on the list's totals would hear nothing.
    @Test("A fix that keeps the volume reaches the detail, Today's recent, the Library and the exercise's sessions")
    func sameVolumeEdit_reachesEveryFollower() async throws {
        let workout = S3Kit.workout(1, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(200, 5)])])
        let stack = try await Kit.stored([workout])
        let stats = stack.stats()
        let detail = LibraryArrivals(stack.workouts.observeWorkout(id: workout.id))
        let recent = LibraryArrivals(stack.workouts.observeRecent(limit: 5))
        let library = LibraryArrivals(stats.observeLibraryStats(recentLimit: 5))
        let sessions = LibraryArrivals(stats.observeExerciseSessions(exerciseID: S3Kit.bench))
        defer {
            detail.cancel()
            recent.cancel()
            library.cancel()
            sessions.cancel()
        }
        _ = await (detail.next(within: .seconds(5)), recent.next(within: .seconds(5)))
        _ = await (library.next(within: .seconds(5)), sessions.next(within: .seconds(5)))
        let bench = workout.exercises[0]
        try await stack.workouts.updateSets(
            [bench.id: Kit.raised(bench.sets, to: .pounds(250), reps: 4)],
            of: workout.id
        )
        let (heardDetail, heardRecent) = await (detail.next(within: .seconds(5)), recent.next(within: .seconds(5)))
        let (heardLibrary, heardSessions) = await (
            library.next(within: .seconds(5)),
            sessions.next(within: .seconds(5))
        )
        #expect(heardDetail??.workout.exercises[0].sets[0].reps.value == 4)
        #expect(heardRecent?.first?.exercises[0].sets[0].weight == .pounds(250))
        #expect(heardLibrary != nil, "the Library's stats")
        #expect(heardSessions != nil, "the exercise's sessions")
    }
}
