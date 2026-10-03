import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: `updateSets` (decision #11's history edit): the derived columns it must compute
/// again, the rows it may touch, the exercises it must refuse, and, since the F05 records follow-up, the records
/// it detects again (notes, question 4; product decision #27).
@Suite("Adversarial S3 · set edits", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutEditAdversarialTests {
    /// The workout row's totals, as stored.
    static func totals(_ stack: S3Kit.Stack) async throws -> [String] {
        try await stack
            .texts("SELECT volume_e7g_reps || ' ' || done_sets || ' ' || total_sets || ' ' || pr_count FROM workout")
    }

    static func totals(of workout: WorkoutState, records: Int) throws -> [String] {
        try ["\(workout.volume.e7gReps()) \(workout.doneSets) \(workout.totalSets) \(records)"]
    }

    @Test("An edit stores each set's e1RM and the workout's totals exactly, and stamps only the rows it changed")
    func edit_recomputesDerivedColumns_andStampsOnlyChanges() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1) // the first workout of its lifts: a baseline, with no record
        try await stack.materialize(workout)
        let stamp = try await stack.texts("SELECT DISTINCT updated_at FROM logged_set")
        stack.clock.advance()
        var edited = workout
        edited.exercises[0].sets[0].weight = .pounds(187.25) // changed: a new estimate
        edited.exercises[0].sets[1].doneAt = nil // unticked: its estimate goes
        edited.exercises[0].sets[2].reps = Reps(clamping: 13) // above 12 reps: its estimate goes
        edited.exercises[0].sets.remove(at: 3) // removed
        try await stack.workouts.updateSets(workoutExerciseID: workout.exercises[0].id, sets: edited.exercises[0].sets)
        #expect(try await stack.workouts.workout(id: workout.id) == edited)
        #expect(try await Self.totals(stack) == Self.totals(of: edited, records: 0))
        let estimates = try await stack.texts("""
        SELECT quote(e1rm_e7g) FROM logged_set WHERE workout_exercise_id = ? AND deleted_at IS NULL ORDER BY position
        """, [workout.exercises[0].id.rawValue.uuidString])
        let expected = try edited.exercises[0].sets.map { set in
            guard set.isDone, let estimate = OneRepMax.brzycki(weight: set.weight, reps: set.reps) else {
                return "NULL"
            }
            return try "\(estimate.e7g())"
        }
        #expect(estimates == expected)
        // Sets 0 to 3 changed; the fifth only moved up a place; the other exercise's three rows did not change.
        let untouched = try await stack.texts("SELECT id FROM logged_set WHERE updated_at = ?", [stamp[0]])
        #expect(Set(untouched) == Set(workout.exercises[1].sets.map(\.id.rawValue.uuidString)))
        #expect(try await stack.texts("SELECT DISTINCT updated_at FROM workout_exercise") == stamp)
        #expect(try await stack.texts("SELECT DISTINCT updated_at FROM personal_record") == [])
    }

    @Test("Removing every set leaves the exercise with none; the totals and every stats query follow")
    func edit_toNoSets() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout)
        var edited = workout
        for index in edited.exercises.indices {
            edited.exercises[index].sets = []
            try await stack.workouts.updateSets(workoutExerciseID: workout.exercises[index].id, sets: [])
        }
        #expect(try await stack.workouts.workout(id: workout.id) == edited)
        #expect(try await Self.totals(stack) == ["0 0 0 0"])
        let stats = stack.stats()
        let always = Date.distantPast ..< Date.distantFuture
        #expect(try await stats.lastPerformance(exerciseID: S3Kit.bench) == nil)
        #expect(try await stats.bestSet(exerciseID: S3Kit.bench) == nil)
        #expect(try await stats.bestE1RM(exerciseID: S3Kit.squat) == nil)
        #expect(try await stats.sessionCount(exerciseID: S3Kit.bench) == 0)
        #expect(try await stats.recentlyLogged(limit: 5) == [])
        #expect(try await stats.weeklyVolume(in: always) == .zero)
        #expect(try await stats.sessionsCompleted(in: always) == 1, "the workout itself is still a session")
        // And back: the same ids revive their rows.
        for exercise in workout.exercises {
            try await stack.workouts.updateSets(workoutExerciseID: exercise.id, sets: exercise.sets)
        }
        #expect(try await stack.workouts.workout(id: workout.id) == workout)
        #expect(try await S2Kit.count(stack.queue, "logged_set") == workout.totalSets)
    }

    enum Target: String, CaseIterable, Sendable {
        case unknownRow, rowOfADeletedWorkout, removedRow, aSetID, aWorkoutID
    }

    @Test("An edit of a row no live workout has throws missingRow and changes nothing", arguments: Target.allCases)
    func edit_ofNoLiveRow_isRefused(target: Target) async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout)
        var row = workout.exercises[0].id
        switch target {
        case .unknownRow: row = S3Kit.rowID(9, 9)
        case .rowOfADeletedWorkout: try await stack.workouts.delete(id: workout.id)
        case .removedRow:
            var smaller = workout
            smaller.exercises.removeFirst()
            try await stack.materialize(smaller)
        case .aSetID: row = WorkoutExerciseID(workout.exercises[0].sets[0].id.rawValue)
        case .aWorkoutID: row = WorkoutExerciseID(workout.id.rawValue)
        }
        stack.clock.advance()
        let before = try await stack.dump()
        await #expect(throws: LedgerPersistenceError.missingRow("workout_exercise \(row.rawValue.uuidString)")) {
            try await stack.workouts.updateSets(workoutExerciseID: row, sets: workout.exercises[0].sets)
        }
        #expect(try await stack.dump() == before)
    }

    @Test("An edit with a sibling row's set, one id twice, an inexact weight or a non-finite tick changes nothing")
    func edit_withBadSets_isRefused() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout)
        stack.clock.advance()
        let before = try await stack.dump()
        let own = workout.exercises[0].sets
        var inexact = own
        inexact[4].weight = .pounds(0.001)
        var endless = own
        endless[4].doneAt = Date(timeIntervalSinceReferenceDate: .nan)
        let sibling = workout.exercises[1].sets[0]
        let cases: [(String, [LoggedSet])] = [
            ("sibling", own + [sibling]), ("twice", own + [own[0]]), ("inexact", inexact), ("non-finite", endless)
        ]
        for (name, sets) in cases {
            await #expect(throws: LedgerPersistenceError.self, "\(name) was stored") {
                try await stack.workouts.updateSets(workoutExerciseID: workout.exercises[0].id, sets: sets)
            }
            #expect(try await stack.dump() == before, "\(name)")
        }
    }
}

/// Records after an edit (F05 records follow-up, product decision #27).
extension WorkoutEditAdversarialTests {
    /// The two bench records `pounds` × 5 sets in `workout` over `over` × 5.
    static func benchRecords(_ pounds: Decimal, over: Decimal, in workout: WorkoutState) -> [PersonalRecord] {
        let five = Reps(clamping: 5)
        func estimate(_ pounds: Decimal) -> PRKind {
            .estimatedOneRepMax(OneRepMax.brzycki(weight: .pounds(pounds), reps: five) ?? .zero)
        }
        return [
            S3Kit.record(S3Kit.bench, estimate(pounds), over: estimate(over), in: workout),
            S3Kit.record(
                S3Kit.bench,
                .weightAtReps(.pounds(pounds), five),
                over: .weightAtReps(.pounds(over), five),
                in: workout
            )
        ]
    }

    /// Notes, question 4, closed by the F05 records follow-up (product decision #27). Until then this pinned what
    /// went stale (the record rows and `pr_count` stayed while every query computed from the sets moved); the
    /// orchestrator's brief for the follow-up turns it into the fix's pin. A corrected typo leaves no record, and
    /// an edit of an earlier workout gives a later one the record it then deserves.
    @Test("After an edit the workout's records and pr_count follow its sets, and so do the later workouts'")
    func edit_detectsRecordsAgain() async throws {
        let stack = try await S3Kit.stack()
        let older = S3Kit.workout(1, endedAt: S3Kit.day(-7), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(200, 5)])])
        let newer = S3Kit.workout(2, [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(225, 5)])])
        let estimate = try #require(OneRepMax.brzycki(weight: .pounds(225), reps: Reps(clamping: 5)))
        try await stack.materialize(older)
        try await stack.materialize(newer)
        let stats = stack.stats()
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == Self.benchRecords(
            225,
            over: 200,
            in: newer
        ))
        var typo = newer.exercises[0].sets
        typo[0].weight = .pounds(125) // the lifter corrects 225 to 125: the record was never real
        try await stack.workouts.updateSets(workoutExerciseID: newer.exercises[0].id, sets: typo)
        let best = try #require(try await stats.bestE1RM(exerciseID: S3Kit.bench))
        #expect(best == OneRepMax.brzycki(weight: .pounds(200), reps: Reps(clamping: 5)))
        #expect(try await stats.bestSet(exerciseID: S3Kit.bench)?.weight == .pounds(200))
        // Both records are gone: 125 × 5 beats nothing. Nothing is counted.
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == [])
        #expect(estimate > best)
        #expect(try await stack.texts("SELECT pr_count FROM workout ORDER BY ended_at") == ["0", "0"])
        // An edit of the older workout, to 100 lb, gives the newer one the records 125 × 5 now deserves.
        var lighter = older.exercises[0].sets
        lighter[0].weight = .pounds(100)
        try await stack.workouts.updateSets(workoutExerciseID: older.exercises[0].id, sets: lighter)
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == Self.benchRecords(
            125,
            over: 100,
            in: newer
        ))
        #expect(try await stack.texts("SELECT pr_count FROM workout ORDER BY ended_at") == ["0", "2"])
    }
}
