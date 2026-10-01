import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: `updateSets` (decision #11's history edit): the derived columns it must compute
/// again, the rows it may touch, the exercises it must refuse, and what it leaves stale (notes, question 4).
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
        let workout = S3Kit.mixed(1)
        let record = S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(215)), in: workout)
        try await stack.materialize(workout, prs: [record])
        let stamp = try await stack.texts("SELECT DISTINCT updated_at FROM logged_set")
        stack.clock.advance()
        var edited = workout
        edited.exercises[0].sets[0].weight = .pounds(187.25) // changed: a new estimate
        edited.exercises[0].sets[1].doneAt = nil // unticked: its estimate goes
        edited.exercises[0].sets[2].reps = Reps(clamping: 13) // above 12 reps: its estimate goes
        edited.exercises[0].sets.remove(at: 3) // removed
        try await stack.workouts.updateSets(workoutExerciseID: workout.exercises[0].id, sets: edited.exercises[0].sets)
        #expect(try await stack.workouts.workout(id: workout.id) == edited)
        #expect(try await Self.totals(stack) == Self.totals(of: edited, records: 1))
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
        #expect(try await stack.texts("SELECT DISTINCT updated_at FROM personal_record") == stamp)
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

    /// (documents) Notes, question 4: `updateSets` does not detect records again. This pins exactly what goes
    /// stale, for F13: the record rows and `pr_count` stay, while every query computed from the sets moves. So
    /// after an edit the history can show a record that no stored set supports.
    @Test("(documents) After an edit the workout's records and pr_count stay, though no set supports them")
    func edit_leavesRecordsStale() async throws {
        let stack = try await S3Kit.stack()
        let older = S3Kit.workout(1, endedAt: S3Kit.day(-7), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(200, 5)])])
        let newer = S3Kit.workout(2, [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(225, 5)])])
        let estimate = try #require(OneRepMax.brzycki(weight: .pounds(225), reps: Reps(clamping: 5)))
        let records = [
            S3Kit.record(S3Kit.bench, .estimatedOneRepMax(estimate), in: newer),
            S3Kit.record(S3Kit.bench, .weightAtReps(.pounds(225), Reps(clamping: 5)), in: newer)
        ]
        try await stack.materialize(older)
        try await stack.materialize(newer, prs: records)
        var typo = newer.exercises[0].sets
        typo[0].weight = .pounds(125) // the lifter corrects 225 to 125: the record was never real
        try await stack.workouts.updateSets(workoutExerciseID: newer.exercises[0].id, sets: typo)
        let stats = stack.stats()
        let best = try #require(try await stats.bestE1RM(exerciseID: S3Kit.bench))
        #expect(best == OneRepMax.brzycki(weight: .pounds(200), reps: Reps(clamping: 5)))
        #expect(try await stats.bestSet(exerciseID: S3Kit.bench)?.weight == .pounds(200))
        // Stale: both records are still listed, above the best any stored set gives, and still counted.
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == records)
        #expect(estimate > best)
        #expect(try await stack.texts("SELECT pr_count FROM workout ORDER BY ended_at") == ["0", "2"])
        // A later edit of the older workout never creates the record it now deserves, either.
        var heavier = older.exercises[0].sets
        heavier[0].weight = .pounds(230)
        try await stack.workouts.updateSets(workoutExerciseID: older.exercises[0].id, sets: heavier)
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == records)
    }
}
