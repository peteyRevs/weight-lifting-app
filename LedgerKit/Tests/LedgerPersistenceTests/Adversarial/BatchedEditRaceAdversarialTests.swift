import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F13 S3 adversarial (G2): `updateSets(_:of:)` on GRDB against the rest of the history and of the app: records against
/// a history materialised afresh, and deletes, other edits and cancellations racing it.
@Suite("Adversarial F13 S3 · the batched edit against others", .tags(.persistence), .timeLimit(.minutes(2)))
struct BatchedEditRaceAdversarialTests {
    private typealias Kit = BatchedEditKit

    // MARK: - Records

    private static func randomHistory(using random: inout SeededGenerator) -> [WorkoutState] {
        let exercises = [S3Kit.bench, S3Kit.squat, S3Kit.row]
        return (1 ... 6).map { number in
            let count = Int.random(in: 1 ... 3, using: &random)
            let rows = exercises.shuffled(using: &random).prefix(count).map { id in
                let sets = (0 ..< Int.random(in: 1 ... 3, using: &random)).map { _ in
                    let pounds = Decimal(Int.random(in: 20 ... 60, using: &random) * 5)
                    return S3Kit.set(pounds, Int.random(in: 1 ... 13, using: &random))
                }
                return S3Kit.RowSpec(id, sets)
            }
            return S3Kit.workout(number, endedAt: S3Kit.day(Double(number) - 10), Array(rows))
        }
    }

    /// `workout` after a few of a lifter's steps, in either unit, and sometimes a large fix, so that records change
    /// hands in both directions.
    private static func randomlyEdited(_ workout: WorkoutState, using random: inout SeededGenerator) -> WorkoutState {
        var draft = workout
        for _ in 0 ... Int.random(in: 0 ... 4, using: &random) {
            let id = draft.exercises.flatMap(\.sets).randomElement(using: &random)?.id ?? SetID(UUID())
            let field: SetEditing.Field = Bool.random(using: &random) ? .weight : .reps
            let way: StepDirection = Bool.random(using: &random) ? .upward : .downward
            let units: Units = Bool.random(using: &random) ? .lb : .kg
            draft = SetEditing.stepping(id, field, way, in: draft, units: units)
        }
        if Bool.random(using: &random) {
            draft.exercises[0].sets[0].weight = .pounds(Decimal(Int.random(in: 0 ... 90, using: &random) * 5))
        }
        return draft
    }

    @Test("After random batched edits, records, counts and the list equal the same history materialised afresh")
    func records_equalAFreshHistory() async throws {
        var recordsSeen = 0
        for seed in 0 ..< Kit.sweep(24, 6) {
            var random = SeededGenerator(seed: UInt64(seed) &+ 0x0F13)
            let workouts = Self.randomHistory(using: &random)
            let stack = try await Kit.stored(workouts)
            for _ in 0 ..< 8 {
                let picked = workouts.randomElement(using: &random) ?? workouts[0]
                let original = try #require(try await stack.workouts.workout(id: picked.id))
                let draft = Self.randomlyEdited(original, using: &random)
                try await stack.workouts.updateSets(SetEditing.changes(from: original, to: draft), of: picked.id)
                stack.clock.advance()
            }
            let fresh = try await S3Kit.stack()
            for workout in try await stack.workouts.recent(limit: 100).reversed() {
                try await fresh.materialize(workout)
            }
            for exercise in [S3Kit.bench, S3Kit.squat, S3Kit.row] {
                let there = try await stack.stats().personalRecords(exerciseID: exercise)
                let here = try await fresh.stats().personalRecords(exerciseID: exercise)
                #expect(there == here, "seed \(seed), exercise \(exercise)")
                recordsSeen += there.count
            }
            let (listed, freshly) = try await (stack.workouts.historyEntries(), fresh.workouts.historyEntries())
            #expect(listed == freshly, "seed \(seed)")
        }
        #expect(recordsSeen > 20, "the comparison saw \(recordsSeen) records")
    }
}

extension BatchedEditRaceAdversarialTests {
    // MARK: - Races

    @Test(
        "A delete racing a save: the workout ends deleted, never brought back, and the save stored or said missingRow"
    )
    func deleteRacingASave_endsDeleted() async throws {
        for round in 0 ..< Kit.sweep(40, 10) {
            let history = Kit.history()
            let (middle, stack) = try await (history.middle, Kit.stored(history.all))
            let bench = middle.exercises[0]
            let workouts = stack.workouts
            let save = Task { () -> (any Error)? in
                do {
                    try await workouts.updateSets([bench.id: Kit.raised(bench.sets, to: .pounds(500))], of: middle.id)
                    return nil
                } catch {
                    return error
                }
            }
            let delete = Task {
                if round.isMultiple(of: 2) {
                    await Task.yield()
                }
                try await workouts.delete(id: middle.id)
            }
            let saveError = await save.value
            try await delete.value
            if let saveError {
                guard case RepositoryError.missingRow = saveError else {
                    Issue.record("round \(round): \(saveError)")
                    continue
                }
            }
            #expect(try await workouts.workout(id: middle.id) == nil, "round \(round)")
            let live = try await stack.texts(
                "SELECT id FROM personal_record WHERE workout_id = ? AND deleted_at IS NULL",
                [ColumnCodec.text(middle.id)]
            )
            #expect(live.isEmpty, "round \(round): the deleted workout's records")
            let held = try await stack.stats().personalRecords(exerciseID: S3Kit.bench).filter {
                $0.workoutID == history.newer.id
            }
            #expect(!held.isEmpty, "round \(round): the newer workout holds the record again")
        }
    }

    @Test("A save after a delete brings nothing back, and an edit in between two reads is seen whole")
    func saveAfterADelete_bringsNothingBack() async throws {
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        let before = try await Kit.rows(of: "logged_set", in: stack)
        try await stack.workouts.delete(id: middle.id)
        let deleted = try await Kit.all(in: stack)
        let bench = middle.exercises[0]
        await #expect(throws: RepositoryError.self) {
            try await stack.workouts.updateSets([bench.id: Kit.raised(bench.sets, to: .pounds(500))], of: middle.id)
        }
        #expect(try await Kit.all(in: stack) == deleted)
        #expect(before.count == deleted["logged_set"]?.count)
    }

    @Test("Two saves racing on different exercises both land, as each reads the workout inside its write")
    func twoSaves_onDifferentExercises_bothLand() async throws {
        for _ in 0 ..< Kit.sweep(20, 5) {
            let history = Kit.history()
            let (middle, stack) = try await (history.middle, Kit.stored(history.all))
            let (bench, squat) = (middle.exercises[0], middle.exercises[1])
            async let first: Void = stack.workouts.updateSets(
                [bench.id: Kit.raised(bench.sets, to: .pounds(500))],
                of: middle.id
            )
            async let second: Void = stack.workouts.updateSets(
                [squat.id: Kit.raised(squat.sets, to: .pounds(600))],
                of: middle.id
            )
            _ = try await (first, second)
            let read = try #require(try await stack.workouts.workout(id: middle.id))
            #expect(read.exercises[0].sets[0].weight == .pounds(500))
            #expect(read.exercises[1].sets[0].weight == .pounds(600))
        }
    }

    /// Decision 3 of the notes, pinned as built: the sheet hands whole exercises from what it read, so a change to a
    /// sibling set between reading and saving is overwritten. Other exercises survive.
    @Test("As built: a stale snapshot overwrites a concurrent edit of a set in the same exercise, and of nothing else")
    func staleSnapshot_overwritesTheSameExerciseOnly() async throws {
        let history = Kit.history()
        let (middle, stack) = try await (history.middle, Kit.stored(history.all))
        let (bench, squat) = (middle.exercises[0], middle.exercises[1])
        let snapshot = SetEditing.stepping(bench.sets[0].id, .reps, .upward, in: middle, units: .lb)
        // Elsewhere, after the sheet read: bench's second set, and squat.
        try await stack.workouts.updateSets(
            [
                bench.id: Kit.raised(bench.sets, at: 1, to: .pounds(400)),
                squat.id: Kit.raised(squat.sets, to: .pounds(600))
            ],
            of: middle.id
        )
        try await stack.workouts.updateSets(SetEditing.changes(from: middle, to: snapshot), of: middle.id)
        let read = try #require(try await stack.workouts.workout(id: middle.id))
        #expect(read.exercises[0].sets[1] == bench.sets[1], "the concurrent edit of bench is lost")
        #expect(read.exercises[1].sets[0].weight == .pounds(600), "squat, which the sheet did not change, survives")
    }

    @Test("A write cancelled at any moment stores all of it or nothing, and what it says agrees")
    func cancelled_isAllOrNothing() async throws {
        for yields in 0 ..< Kit.sweep(30, 8) {
            let history = Kit.history()
            let (middle, stack) = try await (history.middle, Kit.stored(history.all))
            let (bench, squat) = (middle.exercises[0], middle.exercises[1])
            let workouts = stack.workouts
            let run = Task {
                try await workouts.updateSets(
                    [
                        bench.id: Kit.raised(bench.sets, to: .pounds(500)),
                        squat.id: Kit.raised(squat.sets, to: .pounds(600))
                    ],
                    of: middle.id
                )
            }
            for _ in 0 ..< yields {
                await Task.yield()
            }
            run.cancel()
            let threw = await (try? run.value) == nil
            let read = try #require(try await workouts.workout(id: middle.id))
            let stored = read.exercises[0].sets[0].weight == .pounds(500)
            #expect(stored == (read.exercises[1].sets[0].weight == .pounds(600)), "half stored at \(yields)")
            #expect(stored != threw, "at \(yields): threw \(threw), stored \(stored)")
        }
    }
}
