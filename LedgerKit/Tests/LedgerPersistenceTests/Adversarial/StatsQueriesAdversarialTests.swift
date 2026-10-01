import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: the stats queries where the brief leaves room: which kinds of set count, what
/// wins a tie, and whether an answer depends on the order rows were stored in.
@Suite("Adversarial S3 · stats queries", .tags(.persistence), .timeLimit(.minutes(1)))
struct StatsQueriesAdversarialTests {
    static let always = Date.distantPast ..< Date.distantFuture

    /// (documents) Notes, question 6: criterion 5 says "done sets", F12's brief `.working` only, and the slice
    /// follows decision #3. One heavy done set of `kind` beside a light working set shows who counts it.
    @Test(
        "(documents) Which kinds count: the Last line working only, the bests working and added, volume all",
        arguments: SetKind.allCases
    )
    func kinds_countAsDocumented(kind: SetKind) async throws {
        let stack = try await S3Kit.stack()
        let light = S3Kit.workout(1, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(100, 5)])])
        let heavy = S3Kit.workout(2, [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(300, 2, kind)])])
        try await stack.materialize(light)
        try await stack.materialize(heavy)
        let stats = stack.stats()
        let countsForBests = kind == .working || kind == .added
        let top: Decimal = countsForBests ? 300 : 100
        #expect(try await stats.lastPerformance(exerciseID: S3Kit.bench)?.load == .pounds(kind == .working ? 300 : 100))
        #expect(try await stats.bestSet(exerciseID: S3Kit.bench)?.weight == .pounds(top))
        let estimate = OneRepMax.brzycki(weight: .pounds(top), reps: Reps(clamping: countsForBests ? 2 : 5))
        #expect(try await stats.bestE1RM(exerciseID: S3Kit.bench) == estimate)
        let weeks = try await stats.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: 1, calendar: S3Kit.calendar())
        #expect(weeks.values.max() == estimate)
        #expect(try await stats.weeklyVolume(in: Self.always) == light.volume + heavy.volume)
        #expect(try await stats.sessionCount(exerciseID: S3Kit.bench) == 2)
        #expect(try await stats.recentlyLogged(limit: 1) == [S3Kit.bench])
        // The stored estimate does not depend on the kind: the schema's comment, and the notes' decision 8.
        #expect(try await stack.texts("SELECT COUNT(e1rm_e7g) FROM logged_set") == ["2"])
    }

    @Test(
        "Of two workouts that ended together, the Last line reads the smaller id's, whichever was stored first",
        arguments: [
            [1, 2], [2, 1]
        ]
    )
    func lastPerformance_tieOfWorkouts(order: [Int]) async throws {
        let stack = try await S3Kit.stack()
        for number in order {
            let sets = [S3Kit.set(Decimal(100 * number), 5), S3Kit.set(Decimal(100 * number), 7), S3Kit.set(50, 20)]
            try await stack.materialize(S3Kit.workout(number, [S3Kit.RowSpec(S3Kit.bench, sets)]))
        }
        let line = LastPerformance(date: S3Kit.now, sets: 3, reps: 7, load: .pounds(100))
        #expect(try await stack.stats().lastPerformance(exerciseID: S3Kit.bench) == line)
    }

    @Test("The best set of two as heavy has more reps; the best estimate of two equal ones is that one value")
    func bests_ties() async throws {
        let stack = try await S3Kit.stack()
        let rows = [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(200, 3), S3Kit.set(200, 9, .added), S3Kit.set(200, 20, .drop)]),
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(200, 9), S3Kit.set(199.99, 12), S3Kit.set(200, 10, done: false)])
        ]
        try await stack.materialize(S3Kit.workout(1, rows))
        let best = try await stack.stats().bestSet(exerciseID: S3Kit.bench)
        #expect(best?.weight == .pounds(200) && best?.reps.value == 9)
        let estimate = OneRepMax.brzycki(weight: .pounds(199.99), reps: Reps(clamping: 12))
        #expect(try await stack.stats().bestE1RM(exerciseID: S3Kit.bench) == estimate)
    }

    @Test("Exercises logged in one workout list in id order, not row order; an older tie-free one follows")
    func recentlyLogged_ties() async throws {
        let stack = try await S3Kit.stack()
        let one = [S3Kit.set(100, 5)]
        let rows = [S3Kit.press, S3Kit.bench, S3Kit.row, S3Kit.bench].map { S3Kit.RowSpec($0, one) }
        try await stack.materialize(S3Kit.workout(1, rows))
        try await stack.materialize(S3Kit.workout(2, endedAt: S3Kit.day(-1), [S3Kit.RowSpec(S3Kit.squat, one)]))
        try await stack.materialize(S3Kit.workout(3, endedAt: S3Kit.day(-2), [S3Kit.RowSpec(S3Kit.bench, one)]))
        let expected = [S3Kit.bench, S3Kit.row, S3Kit.press, S3Kit.squat]
        #expect(try await stack.stats().recentlyLogged(limit: 10) == expected)
        #expect(try await stack.stats().recentlyLogged(limit: 3) == Array(expected.prefix(3)))
    }

    @Test(
        "Records achieved at one instant list the same way whatever order their workouts were stored in",
        arguments: 0 ..< 6
    )
    func personalRecords_orderIsDeterministic(rotation: Int) async throws {
        var workouts = (1 ... 3).map { S3Kit.workout(
            $0,
            endedAt: S3Kit.day(Double($0)),
            [S3Kit.RowSpec(S3Kit.bench, [])]
        ) }
        func records(_ workout: WorkoutState) -> [PersonalRecord] {
            [
                S3Kit.record(S3Kit.bench, .weightAtReps(.pounds(200), Reps(clamping: 5)), in: workout, at: S3Kit.now),
                S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(230)), in: workout, at: S3Kit.now),
                S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(231)), in: workout, at: S3Kit.day(1))
            ]
        }
        let reference = try await S3Kit.stack()
        for workout in workouts {
            try await reference.materialize(workout, prs: records(workout))
        }
        let expected = try await reference.stats().personalRecords(exerciseID: S3Kit.bench)
        #expect(expected.count == 9)
        #expect(expected.prefix(3).allSatisfy { $0.achievedAt == S3Kit.day(1) })
        #expect(expected.dropFirst(3).prefix(3).allSatisfy { $0.kind == .estimatedOneRepMax(.pounds(230)) })
        workouts.swapAt(rotation % 3, (rotation / 3 + 1) % 3)
        let stack = try await S3Kit.stack()
        for workout in workouts.reversed() {
            try await stack.materialize(workout, prs: records(workout))
            try await stack.materialize(workout, prs: records(workout))
        }
        #expect(try await stack.stats().personalRecords(exerciseID: S3Kit.bench) == expected)
    }

    @Test("A row swapped to another exercise, or dropped by a rebuild, stops counting for the first exercise")
    func swappedOrDroppedRow_stopsCounting() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout)
        var swapped = workout
        swapped.exercises[0].exerciseID = S3Kit.press
        try await stack.materialize(swapped)
        let stats = stack.stats()
        #expect(try await stats.lastPerformance(exerciseID: S3Kit.bench) == nil)
        #expect(try await stats.sessionCount(exerciseID: S3Kit.bench) == 0)
        #expect(try await stats.bestSet(exerciseID: S3Kit.press)?.weight == .pounds(190))
        #expect(try await stats.recentlyLogged(limit: 5) == [S3Kit.squat, S3Kit.press])
        var dropped = swapped
        dropped.exercises.removeFirst()
        try await stack.materialize(dropped)
        #expect(try await stats.bestSet(exerciseID: S3Kit.press) == nil)
        #expect(try await stats.weeklyVolume(in: Self.always) == dropped.volume)
        #expect(try await stats.recentlyLogged(limit: 5) == [S3Kit.squat])
    }

    @Test("With every workout deleted, each query answers as on an empty database")
    func onlyDeletedWorkouts_readAsEmpty() async throws {
        let stack = try await S3Kit.stack()
        for number in 1 ... 3 {
            let workout = S3Kit.mixed(number, endedAt: S3Kit.day(Double(-number)))
            let record = S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(215)), in: workout)
            try await stack.materialize(workout, prs: [record])
            try await stack.workouts.delete(id: workout.id)
        }
        let stats = stack.stats()
        #expect(try await stats.lastPerformance(exerciseID: S3Kit.bench) == nil)
        #expect(try await stats.bestSet(exerciseID: S3Kit.bench) == nil)
        #expect(try await stats.bestE1RM(exerciseID: S3Kit.bench) == nil)
        #expect(try await stats.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: .max, calendar: S3Kit.calendar()) == [:])
        #expect(try await stats.weeklyVolume(in: Self.always) == .zero)
        #expect(try await stats.sessionsCompleted(in: Self.always) == 0)
        #expect(try await stats.sessionCount(exerciseID: S3Kit.bench) == 0)
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == [])
        #expect(try await stats.recentlyLogged(limit: 10) == [])
    }
}

extension StatsQueriesAdversarialTests {
    /// (documents) Finding S3-N3. Volume sums reps per weight in SQL. Each workout's own volume must fit its
    /// column, but across workouts the reps at one weight can pass `Int64`: SQLite then fails the query, which
    /// is loud, and needs 2⁶³ reps at one weight.
    @Test(
        "(documents) Reps at one weight summing beyond Int64 fail weeklyVolume with SQLite's overflow error",
        .enabled(if: Int.bitWidth == 64, "two sets cannot hold 2⁶³ reps where Int is 32 bits")
    )
    func volume_overflowsLoudly() async throws {
        let stack = try await S3Kit.stack()
        for number in 1 ... 2 {
            var workout = S3Kit.workout(number, [S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(1, 1)])])
            workout.exercises[0].sets[0].weight = Weight(e7g: 1)
            workout.exercises[0].sets[0].reps = Reps(clamping: .max)
            try await stack.materialize(workout)
        }
        await #expect(throws: DatabaseError.self) { _ = try await stack.stats().weeklyVolume(in: Self.always) }
    }
}
