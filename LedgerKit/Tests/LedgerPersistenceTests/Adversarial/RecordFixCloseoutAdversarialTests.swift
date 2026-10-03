import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 records follow-up, close-out round: the fixes of R-1 (stored records already as found left out of the diff),
/// R-Q1 (a workout the replay cannot read is skipped and logged) and R-SF2 (a recount stamps nothing), attacked for
/// regressions, as S2-5 was a regression of S2-1's fix.
@Suite("Adversarial records close-out · the fixes", .tags(.persistence), .timeLimit(.minutes(1)))
struct RecordFixCloseoutAdversarialTests {
    static func session(_ number: Int, day: Double, bench: Decimal?, squat: Decimal?) -> WorkoutState {
        var rows: [S3Kit.RowSpec] = []
        if let bench {
            rows.append(S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(bench, 5)]))
        }
        if let squat {
            rows.append(S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(squat, 5)]))
        }
        return S3Kit.workout(number, endedAt: S3Kit.day(day), rows)
    }

    /// A, then W (bench and squat, its bench damaged), then B and C, squat only.
    static let history = [
        session(1, day: -9, bench: nil, squat: 100),
        session(2, day: -7, bench: 150, squat: 200),
        session(3, day: -5, bench: nil, squat: 150),
        session(4, day: -3, bench: nil, squat: 210)
    ]

    static func damaged() async throws -> S3Kit.Stack {
        let stack = try await S3Kit.stack()
        for workout in history {
            try await stack.materialize(workout)
        }
        try await stack.execute("UPDATE logged_set SET reps = 0 WHERE workout_exercise_id = ?", [
            history[1].exercises[0].id.rawValue.uuidString
        ])
        return stack
    }

    static func squatRecords(_ stack: S3Kit.Stack) async throws -> [String] {
        try await stack.stats().personalRecords(exerciseID: S3Kit.squat).map { "\($0.workoutID) \($0.kind)" }
    }

    /// Finding R-2. The walk leaves out a whole workout when any row it reads fails, and what it reads is the
    /// write's lifts only. So workout W, whose bench is damaged, counts for squat in a squat-only write and not in a
    /// write that also covers bench: the stored squat records depend on which write came last.
    @Test("The squat records of one history do not depend on whether the last write also covered the damaged bench")
    func damagedOtherLift_doesNotChangeTheRecords() async throws {
        let squatOnly = try await Self.damaged()
        try await squatOnly.workouts.updateSets(
            workoutExerciseID: Self.history[2].exercises[0].id,
            sets: Self.history[2].exercises[0].sets
        )
        try await squatOnly.materialize(Self.history[3]) // squat only: W's squat 200 counts, so C's 210 is the record
        let both = try await Self.damaged()
        var rebuilt = Self.history[2]
        rebuilt.exercises.append(S3Kit.exercise(3, 5, S3Kit.RowSpec(S3Kit.bench, []), doneAt: S3Kit.now))
        try await both.materialize(rebuilt) // bench and squat: W is left out of both
        var plain = rebuilt
        plain.exercises.removeLast()
        try await both.materialize(plain) // the same history as `squatOnly`, written with bench in scope
        #expect(try await Self.squatRecords(both) == Self.squatRecords(squatOnly))
    }

    /// Finding R-2, through the public query: asked with bench, the fallback walk leaves W out whole.
    @Test("bests(before:for:) of a lift does not depend on which other lifts are asked with it")
    func bestsOfALift_doNotDependOnTheOthersAsked() async throws {
        let stack = try await Self.damaged()
        let next = Self.history[2] // after W, whose squat 200 is the best so far
        let alone = try await stack.stats().bests(before: next, for: [S3Kit.squat])
        let together = try await stack.stats().bests(before: next, for: [S3Kit.squat, S3Kit.bench])
        #expect(alone.e1RM[S3Kit.squat] == together.e1RM[S3Kit.squat])
        #expect(alone.weightAtReps[S3Kit.squat] == together.weightAtReps[S3Kit.squat])
    }

    @Test(
        "A record row tampered in any column, its id kept, is rewritten by the next write that replays it",
        arguments: [
            "weight_e7g = weight_e7g + 1", "previous_weight_e7g = 1",
            "previous_kind = NULL, previous_weight_e7g = NULL",
            "previous_reps = 9", "achieved_at = achieved_at + 0.001", "achieved_at = CAST(achieved_at AS TEXT)",
            "reps = 4", "kind = 'weightAtReps'", "exercise_id = lower(exercise_id)"
        ]
    )
    func tamperedRecordRow_isRewritten(damage: String) async throws {
        let stack = try await S3Kit.stack()
        try await stack.materialize(S3Kit.baseline)
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout)
        let rows = try await RecordReplayEdgeAdversarialTests.derived(stack)
        try await stack.execute("UPDATE personal_record SET \(damage) WHERE kind = 'estimatedOneRepMax'")
        // An edit of the earlier workout that changes nothing replays bench from there.
        try await stack.workouts.updateSets(
            workoutExerciseID: S3Kit.baseline.exercises[0].id,
            sets: S3Kit.baseline.exercises[0].sets
        )
        #expect(try await RecordReplayEdgeAdversarialTests.derived(stack) == rows)
        #expect(try await stack.stats().personalRecords(exerciseID: S3Kit.bench) == S3Kit.mixedRecords(of: workout))
    }

    @Test("A write that changes a workout and its record count stamps that workout once, and no other")
    func contentAndCount_stampOnce() async throws {
        let stack = try await S3Kit.stack()
        let workouts = (1 ... 4)
            .map { Self.session($0, day: Double(-10 + $0), bench: Decimal(100 + 10 * $0), squat: nil) }
        for workout in workouts {
            try await stack.materialize(workout)
        }
        let before = try await stack.texts("SELECT id || ' ' || updated_at FROM workout ORDER BY id")
        stack.clock.advance()
        var typo = workouts[1]
        typo.exercises[0].sets[0].weight = .pounds(500) // its counts and the later ones' change
        try await stack.materialize(typo)
        let after = try await stack.texts("SELECT id || ' ' || updated_at || ' ' || pr_count FROM workout ORDER BY id")
        let stamp = ColumnCodec.timestamp(stack.clock.now)
        #expect(after.filter { $0.contains(stamp) }.map { String($0.prefix(36)) } == [typo.id.rawValue.uuidString])
        #expect(try await stack.texts("SELECT pr_count FROM workout ORDER BY started_at") == ["0", "2", "0", "0"])
        #expect(before.count == 4)
    }
}
