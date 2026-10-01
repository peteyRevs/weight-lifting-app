import Foundation
import LedgerDomain

/// Weeks, sessions, personal records, recently logged exercises, and edits.
extension StatsQueriesContract {
    /// Criterion 5. Bench in ten consecutive weeks, the current one first: `weeksAgo` 0 to 9. Week 3 has no
    /// workout and week 5 only sets of 15 reps, so neither has a key; week 1 has two workouts, and the better
    /// estimate wins; weeks 8 and 9 are outside the last 8, and so is a workout dated next week.
    static func e1RMByWeek(_ stores: HistoryStores) async throws -> String? {
        let calendar = try calendar
        typealias Session = (weeksAgo: Int, set: Seeders.SetSpec)
        let best: [Session] = [
            (0, .init(195, 5)), (1, .init(185, 8)), (2, .init(190, 4)), (4, .init(180, 6)), (6, .init(175, 5)),
            (7, .init(170, 5))
        ]
        let others: [Session] = [
            (1, .init(190, 5)), (5, .init(100, 15)), (8, .init(300, 1)), (9, .init(300, 1)), (-1, .init(400, 1))
        ]
        for (number, session) in (others + best).enumerated() {
            try await stores.materialize(Seeders.workout(number: number, endedAt: day(-7 * session.weeksAgo), [
                Seeders.ExerciseLog(bench, Array(repeating: session.set, count: 3)),
                .straight(row, sets: 3, reps: 5, pounds: 500)
            ]))
        }
        var expected: [WeekKey: Weight] = [:]
        for session in best {
            expected[calendar.isoWeekKey(for: day(-7 * session.weeksAgo))] = OneRepMax.brzycki(
                weight: session.set.weight,
                reps: Reps(clamping: session.set.reps)
            )
        }
        let stats = stores.stats
        let none = try await stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 0, calendar: calendar)
        let one = try await stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 1, calendar: calendar)
        return try await ContractCheck.first(
            ContractCheck.expect(
                stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 8, calendar: calendar),
                expected,
                "e1RMByWeek(lastWeeks: 8)"
            ),
            ContractCheck.expect(none, [:], "e1RMByWeek(lastWeeks: 0)"),
            ContractCheck.expect(
                one,
                [calendar.isoWeekKey(for: now): e1RM(195, 5) ?? .zero],
                "e1RMByWeek(lastWeeks: 1)"
            )
        )
    }

    /// Criterion 6. Two workouts this week (one ending on the week's first instant) and one in the previous
    /// complete week, each with drop, added and warm-up sets and a set left undone. Each week's volume is the
    /// sum of its workouts' `WorkoutState.volume`, and the Today delta is their difference.
    static func weeklyVolume(_ stores: HistoryStores) async throws -> String? {
        let calendar = try calendar
        let thisWeek = calendar.week(containing: now)
        let lastWeek = calendar.previousCompleteWeek(before: now)
        let current = [
            Workouts.workout(number: 0, endedAt: now),
            Workouts.workout(number: 1, endedAt: thisWeek.lowerBound)
        ]
        let previous = Seeders.workout(number: 2, endedAt: lastWeek.lowerBound.addingTimeInterval(3600), [
            Seeders.ExerciseLog(
                bench,
                [.init(180, 5), .init(180, 5), .init(152.5, 7, .drop), .init(185, 3, done: false)]
            )
        ])
        for workout in current + [previous] {
            try await stores.materialize(workout)
        }
        let volume = try await stores.stats.weeklyVolume(in: thisWeek)
        let before = try await stores.stats.weeklyVolume(in: lastWeek)
        let expected = current[0].volume + current[1].volume
        let both = try await stores.stats.weeklyVolume(in: lastWeek.lowerBound ..< thisWeek.upperBound)
        return ContractCheck.first(
            ContractCheck.expect(volume, expected, "this week's volume"),
            ContractCheck.expect(before, Volume(gramReps: Weight.pounds(2867.5).grams), "last week's volume"),
            ContractCheck.expect(volume - before, expected - previous.volume, "the Today delta"),
            ContractCheck.expect(both, expected + previous.volume, "the volume of both weeks")
        )
    }

    static func sessions(_ stores: HistoryStores) async throws -> String? {
        let calendar = try calendar
        let thisWeek = calendar.week(containing: now)
        let lastWeek = calendar.previousCompleteWeek(before: now)
        let undone = Seeders.ExerciseLog(bench, [.init(180, 5, done: false)])
        let workouts = [
            Seeders.workout(number: 0, endedAt: thisWeek.lowerBound, [.straight(bench, sets: 3, reps: 5, pounds: 180)]),
            Seeders.workout(number: 1, endedAt: now, [undone, .straight(row, sets: 3, reps: 8, pounds: 70)]),
            Seeders.workout(number: 2, endedAt: day(1), [Seeders.ExerciseLog(bench, [.init(60, 10, .warmup)])]),
            Seeders.workout(number: 3, endedAt: lastWeek.lowerBound.addingTimeInterval(-1), []),
            Seeders.workout(number: 4, endedAt: lastWeek.lowerBound, [.straight(row, sets: 1, reps: 8, pounds: 70)])
        ]
        for workout in workouts {
            try await stores.materialize(workout)
        }
        let stats = stores.stats
        return try await ContractCheck.first(
            ContractCheck.expect(stats.sessionsCompleted(in: thisWeek), 3, "sessions this week"),
            ContractCheck.expect(stats.sessionsCompleted(in: lastWeek), 1, "sessions last week"),
            ContractCheck.expect(stats.sessionCount(exerciseID: bench.id), 2, "bench sessions: done sets only"),
            ContractCheck.expect(stats.sessionCount(exerciseID: row.id), 2, "row sessions")
        )
    }

    static func personalRecords(_ stores: HistoryStores) async throws -> String? {
        let first = Workouts.workout(number: 0, endedAt: day(-7))
        let second = Workouts.workout(number: 1, endedAt: now)
        func record(
            _ exercise: Exercise,
            _ kind: PRKind,
            _ previous: PRKind?,
            in workout: WorkoutState
        ) -> PersonalRecord {
            PersonalRecord(
                exerciseID: exercise.id,
                kind: kind,
                previous: previous,
                achievedAt: workout.endedAt ?? now,
                workoutID: workout.id
            )
        }
        let five = Reps(clamping: 5)
        let early = record(bench, .weightAtReps(.pounds(185), five), nil, in: first)
        let estimate = record(
            bench, .estimatedOneRepMax(.pounds(208)), .estimatedOneRepMax(.pounds(205)), in: second
        )
        let weight = record(
            bench, .weightAtReps(.pounds(190), five), .weightAtReps(.pounds(185), Reps(clamping: 6)), in: second
        )
        let other = record(row, .estimatedOneRepMax(.kilograms(60)), .estimatedOneRepMax(.kilograms(57.5)), in: second)
        try await stores.materialize(first, prs: [early])
        try await stores.materialize(second, prs: [weight, other, estimate])
        let stats = stores.stats
        let all = try await stats.personalRecords(exerciseID: bench.id)
        let others = try await stats.personalRecords(exerciseID: row.id)
        try await stores.materialize(second, prs: [other, weight]) // a rebuild that no longer finds the estimate
        let afterRebuild = try await stats.personalRecords(exerciseID: bench.id)
        try await stores.workouts.delete(id: first.id)
        return try await ContractCheck.first(
            ContractCheck.expect(all, [estimate, weight, early], "bench records, newest first"),
            ContractCheck.expect(others, [other], "row records"),
            ContractCheck.expect(afterRebuild, [weight, early], "bench records after the rebuild"),
            ContractCheck.expect(stats.personalRecords(exerciseID: bench.id), [weight], "after the delete")
        )
    }

    static func recentlyLogged(_ stores: HistoryStores) async throws -> String? {
        let undone = Seeders.ExerciseLog(Workouts.exercises[3], [.init(100, 12, done: false)])
        let workouts = [
            Seeders.workout(number: 0, endedAt: day(-3), [.straight(bench, sets: 1, reps: 5, pounds: 180)]),
            Seeders.workout(number: 1, endedAt: day(-2), [.straight(row, sets: 1, reps: 8, pounds: 70), undone]),
            Seeders.workout(number: 2, endedAt: day(-1), [.straight(squat, sets: 1, reps: 5, pounds: 250)]),
            Seeders.workout(number: 3, endedAt: now, [.straight(bench, sets: 1, reps: 5, pounds: 185)])
        ]
        for workout in workouts {
            try await stores.materialize(workout)
        }
        let stats = stores.stats
        return try await ContractCheck.first(
            ContractCheck.expect(stats.recentlyLogged(limit: 5), [bench.id, squat.id, row.id], "limit 5"),
            ContractCheck.expect(stats.recentlyLogged(limit: 2), [bench.id, squat.id], "limit 2"),
            ContractCheck.expect(stats.recentlyLogged(limit: 0), [], "limit 0"),
            ContractCheck.expect(stats.recentlyLogged(limit: -1), [], "limit -1")
        )
    }

    static func followsEdits(_ stores: HistoryStores) async throws -> String? {
        let calendar = try calendar
        let week = calendar.week(containing: now)
        let older = Seeders.workout(number: 0, endedAt: day(-1), [.straight(bench, sets: 3, reps: 5, pounds: 170)])
        let newer = Seeders.workout(number: 1, endedAt: now, [.straight(bench, sets: 3, reps: 5, pounds: 180)])
        try await stores.materialize(older)
        try await stores.materialize(newer)
        var sets = newer.exercises[0].sets
        sets[0].weight = .pounds(200)
        sets[0].reps = Reps(clamping: 2)
        sets[2].doneAt = nil
        try await stores.workouts.updateSets(workoutExerciseID: newer.exercises[0].id, sets: sets)
        let stats = stores.stats
        let line = try await stats.lastPerformance(exerciseID: bench.id)
        let estimate = try await stats.bestE1RM(exerciseID: bench.id)
        let volume = try await stats.weeklyVolume(in: week)
        let edited = Volume(gramReps: Weight.pounds(200 * 2 + 180 * 5).grams)
        try await stores.workouts.delete(id: newer.id)
        return try await ContractCheck.first(
            ContractCheck.expect(
                line,
                LastPerformance(date: now, sets: 2, reps: 2, load: .pounds(200)),
                "lastPerformance after updateSets"
            ),
            ContractCheck.expect(estimate, e1RM(200, 2), "bestE1RM after updateSets"),
            ContractCheck.expect(volume, older.volume + edited, "weeklyVolume after updateSets"),
            ContractCheck.expect(stats.bestE1RM(exerciseID: bench.id), e1RM(170, 5), "bestE1RM after delete"),
            ContractCheck.expect(stats.weeklyVolume(in: week), older.volume, "weeklyVolume after delete"),
            ContractCheck.expect(stats.sessionsCompleted(in: week), 1, "sessionsCompleted after delete")
        )
    }
}
