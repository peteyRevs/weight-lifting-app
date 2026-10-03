import Foundation
import LedgerDomain

/// Weeks, sessions, personal records, recently logged exercises, and edits.
extension StatsQueriesContract {
    /// Criterion 5. Bench in ten consecutive weeks, the current one included. Each workout has three sets of
    /// its load, and a drop set and a warm-up with far higher estimates, which no week counts.
    /// - The week four weeks back has no workout and the one five weeks back only sets of 15 reps, so neither
    ///   has a key. Last week has four workouts, and the best estimate wins.
    /// - The workouts eight and nine weeks back are outside the last 8, and so is one dated next week.
    /// - A workout belongs to the week it **started** in (product decision #26): last week's best began at 23:30
    ///   on Sunday and ended at 00:40 on Monday, with its bench sets ticked after midnight. The current week's
    ///   best began ten minutes into the week.
    /// - The weeks are the calendar's: with weeks starting on Sunday, last week's Sunday workouts are the
    ///   current week's, and the late one is its best.
    static func e1RMByWeek(_ stores: HistoryStores) async throws -> String? {
        let calendar = try calendar
        let monday = calendar.week(containing: now).lowerBound
        typealias Session = (startedAt: Date, set: Seeders.SetSpec)
        let late: Session = (monday.addingTimeInterval(-1800), .init(215, 5))
        let best: [Session] = [
            (monday.addingTimeInterval(600), .init(205, 5)), late,
            (day(-14), .init(190, 4)), (day(-21), .init(180, 6)), (day(-42), .init(175, 5)), (day(-49), .init(170, 5))
        ]
        let others: [Session] = [
            (now, .init(195, 5)), (day(-7), .init(185, 8)), (day(-7), .init(190, 5)), (day(-35), .init(100, 15)),
            (day(-56), .init(300, 1)), (day(-63), .init(300, 1)), (day(7), .init(400, 1)),
            (monday.addingTimeInterval(-12 * 3600), .init(210, 5))
        ]
        for (number, session) in (others + best).enumerated() {
            let isLate = session.startedAt == late.startedAt
            try await materializeWeek(number, startedAt: session.startedAt, session.set, late: isLate, in: stores)
        }
        var expected: [WeekKey: Weight] = [:]
        for session in best {
            expected[calendar.isoWeekKey(for: session.startedAt)] = e1RM(session.set)
        }
        let sundays = try Self.calendar(weekStart: .sunday)
        let stats = stores.stats
        let eight = try await stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 8, calendar: calendar)
        let none = try await stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 0, calendar: calendar)
        let one = try await stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 1, calendar: calendar)
        let fromSunday = try await stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 1, calendar: sundays)
        return ContractCheck.first(
            ContractCheck.expect(eight, expected, "e1RMByWeek(lastWeeks: 8)"),
            ContractCheck.expect(none, [:], "e1RMByWeek(lastWeeks: 0)"),
            ContractCheck.expect(one, [calendar.isoWeekKey(for: now): e1RM(best[0].set)], "e1RMByWeek(lastWeeks: 1)"),
            ContractCheck.expect(
                fromSunday,
                [sundays.isoWeekKey(for: now): e1RM(late.set)],
                "e1RMByWeek(lastWeeks: 1) with weeks starting on Sunday"
            )
        )
    }

    /// A bench workout of three sets of `set`, a drop set and a warm-up with far higher estimates, after three
    /// rows of another exercise. It lasts an hour, or 70 minutes when `late`, so a late one's bench sets are
    /// ticked after midnight.
    private static func materializeWeek(
        _ number: Int,
        startedAt start: Date,
        _ set: Seeders.SetSpec,
        late: Bool,
        in stores: HistoryStores
    ) async throws {
        let minutes = late ? 70 : 60
        let uncounted: [Seeders.SetSpec] = [.init(500, 1, .drop), .init(450, 2, .warmup)]
        try await stores.materialize(Seeders.workout(
            number: number,
            endedAt: Workouts.ending(startedAt: start, minutes: minutes),
            minutes: minutes,
            [
                .straight(row, sets: 3, reps: 5, pounds: 500),
                Seeders.ExerciseLog(bench, Array(repeating: set, count: 3) + uncounted)
            ]
        ))
    }

    /// The Brzycki estimate of `set`; `.zero` above 12 reps, which no expected value here has.
    private static func e1RM(_ set: Seeders.SetSpec) -> Weight {
        OneRepMax.brzycki(weight: set.weight, reps: Reps(clamping: set.reps)) ?? .zero
    }

    /// Criterion 6. Two workouts this week (one starting on the week's first instant) and two in the previous
    /// complete week, each with drop, added and warm-up sets and a set left undone. Each week's volume is the
    /// sum of its workouts' `WorkoutState.volume`, and the Today delta is their difference. One of last week's
    /// began at 23:30 on its last day and ended after midnight: it is last week's (product decision #26).
    static func weeklyVolume(_ stores: HistoryStores) async throws -> String? {
        let calendar = try calendar
        let thisWeek = calendar.week(containing: now)
        let lastWeek = calendar.previousCompleteWeek(before: now)
        let current = [
            Workouts.workout(number: 0, endedAt: now),
            Workouts.workout(number: 1, endedAt: Workouts.ending(startedAt: thisWeek.lowerBound))
        ]
        let previous = Seeders.workout(number: 2, endedAt: Workouts.ending(startedAt: lastWeek.lowerBound), [
            Seeders.ExerciseLog(
                bench,
                [.init(180, 5), .init(180, 5), .init(152.5, 7, .drop), .init(185, 3, done: false)]
            )
        ])
        let lateStart = thisWeek.lowerBound.addingTimeInterval(-1800)
        let late = Workouts.workout(number: 3, endedAt: Workouts.ending(startedAt: lateStart, minutes: 70), minutes: 70)
        for workout in current + [previous, late] {
            try await stores.materialize(workout)
        }
        let volume = try await stores.stats.weeklyVolume(in: thisWeek)
        let before = try await stores.stats.weeklyVolume(in: lastWeek)
        let expected = current[0].volume + current[1].volume
        let both = try await stores.stats.weeklyVolume(in: lastWeek.lowerBound ..< thisWeek.upperBound)
        return ContractCheck.first(
            ContractCheck.expect(volume, expected, "this week's volume"),
            ContractCheck.expect(before, previous.volume + late.volume, "last week's volume"),
            ContractCheck.expect(previous.volume, Volume(gramReps: Weight.pounds(2867.5).grams), "a week's arithmetic"),
            ContractCheck.expect(volume - before, expected - previous.volume - late.volume, "the Today delta"),
            ContractCheck.expect(both, expected + previous.volume + late.volume, "the volume of both weeks")
        )
    }

    /// `sessionsCompleted` counts the workouts that started in a range (product decision #26), with or without
    /// a done set: last week holds an empty workout, one on the week's first instant, and one begun at 23:30 on
    /// its last day that ended after midnight; not the one a second before the week. `sessionCount` counts the
    /// workouts with a done set of the exercise, of any kind. A workout that performs bench in two rows is one
    /// session, and its working sets are one "Last" line, dated when the workout started.
    static func sessions(_ stores: HistoryStores) async throws -> String? {
        let calendar = try calendar
        let thisWeek = calendar.week(containing: now)
        let lastWeek = calendar.previousCompleteWeek(before: now)
        let undone = Seeders.ExerciseLog(bench, [.init(180, 5, done: false)])
        let twice: [Seeders.ExerciseLog] = [
            .straight(bench, sets: 3, reps: 5, pounds: 180), .straight(bench, sets: 1, reps: 3, pounds: 190)
        ]
        let rowOnce: [Seeders.ExerciseLog] = [.straight(row, sets: 1, reps: 8, pounds: 70)]
        func starting(_ start: Date, minutes: Int = 60) -> Date {
            Workouts.ending(startedAt: start, minutes: minutes)
        }
        let late = thisWeek.lowerBound.addingTimeInterval(-1800)
        let workouts = [
            Seeders.workout(number: 0, endedAt: starting(thisWeek.lowerBound), twice),
            Seeders.workout(number: 1, endedAt: now, [undone, .straight(row, sets: 3, reps: 8, pounds: 70)]),
            Seeders.workout(number: 2, endedAt: day(1), [Seeders.ExerciseLog(bench, [.init(60, 10, .warmup)])]),
            Seeders.workout(number: 3, endedAt: starting(lastWeek.lowerBound.addingTimeInterval(1)), []),
            Seeders.workout(number: 4, endedAt: starting(lastWeek.lowerBound), rowOnce),
            Seeders.workout(number: 5, endedAt: starting(lastWeek.lowerBound.addingTimeInterval(-1)), []),
            Seeders.workout(number: 6, endedAt: starting(late, minutes: 70), minutes: 70, rowOnce)
        ]
        for workout in workouts {
            try await stores.materialize(workout)
        }
        let stats = stores.stats
        let line = LastPerformance(date: thisWeek.lowerBound, sets: 4, reps: 3, load: .pounds(190))
        return try await ContractCheck.first(
            ContractCheck.expect(stats.sessionsCompleted(in: thisWeek), 3, "sessions this week"),
            ContractCheck.expect(stats.sessionsCompleted(in: lastWeek), 3, "sessions last week, the late one included"),
            ContractCheck.expect(stats.sessionCount(exerciseID: bench.id), 2, "bench sessions: done sets only"),
            ContractCheck.expect(stats.sessionCount(exerciseID: row.id), 3, "row sessions"),
            ContractCheck.expect(stats.lastPerformance(exerciseID: bench.id), line, "the Last line of two rows")
        )
    }

    /// Exercises list by the workout they were last done in, newest first. The newest workout has two done
    /// exercises: they list in id order, whatever their order in the workout.
    static func recentlyLogged(_ stores: HistoryStores) async throws -> String? {
        let undone = Seeders.ExerciseLog(Workouts.exercises[3], [.init(100, 12, done: false)])
        let workouts = [
            Seeders.workout(number: 0, endedAt: day(-3), [.straight(bench, sets: 1, reps: 5, pounds: 180)]),
            Seeders.workout(number: 1, endedAt: day(-2), [.straight(row, sets: 1, reps: 8, pounds: 70), undone]),
            Seeders.workout(number: 2, endedAt: day(-1), [.straight(squat, sets: 1, reps: 5, pounds: 250)]),
            Seeders.workout(number: 3, endedAt: now, [
                .straight(squat, sets: 1, reps: 5, pounds: 255), .straight(bench, sets: 1, reps: 5, pounds: 185)
            ])
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

    /// An edit moves everything computed from sets, and a delete removes the workout from every query. The
    /// workout's records follow the edit (product decision #27), and go with a delete.
    static func followsEdits(_ stores: HistoryStores) async throws -> String? {
        let week = try calendar.week(containing: now)
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
        let records = try await stats.personalRecords(exerciseID: bench.id)
        let editedRecords = [
            record(bench, Self.estimate(200, 2), over: Self.estimate(170, 5), in: newer),
            record(bench, weight(200, 2), over: weight(170, 5), in: newer)
        ]
        let edited = Volume(gramReps: Weight.pounds(200 * 2 + 180 * 5).grams)
        try await stores.workouts.delete(id: newer.id)
        return try await ContractCheck.first(
            ContractCheck.expect(
                line,
                LastPerformance(date: now.addingTimeInterval(-3600), sets: 2, reps: 2, load: .pounds(200)),
                "lastPerformance after updateSets"
            ),
            ContractCheck.expect(estimate, e1RM(200, 2), "bestE1RM after updateSets"),
            ContractCheck.expect(volume, older.volume + edited, "weeklyVolume after updateSets"),
            ContractCheck.expect(records, editedRecords, "personalRecords after updateSets"),
            ContractCheck.expect(stats.bestE1RM(exerciseID: bench.id), e1RM(170, 5), "bestE1RM after delete"),
            ContractCheck.expect(stats.weeklyVolume(in: week), older.volume, "weeklyVolume after delete"),
            ContractCheck.expect(stats.sessionsCompleted(in: week), 1, "sessionsCompleted after delete"),
            ContractCheck.expect(stats.personalRecords(exerciseID: bench.id), [], "personalRecords after delete")
        )
    }
}
