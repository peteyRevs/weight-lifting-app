import Foundation
import LedgerDomain

/// The Library's batch read (F12 S1, N3): `bestSets()` is `bestSet(exerciseID:)` of every exercise, in one read.
extension StatsQueriesContract {
    /// Empty, then over a history that reaches every rule of the best set:
    /// - bench's best is 200 × 3, an added set, over a 200 × 2 and over a heavier set left undone, a heavier drop
    ///   set and a heavier warm-up;
    /// - the row's is 300 × 10, the more reps of two sets as heavy, in two workouts;
    /// - the squat's 315 × 5 is in a workout that is deleted, so the squat has no entry;
    /// - the fourth exercise has only warm-ups and no entry; the fifth and sixth were never logged.
    ///
    /// Every exercise's entry equals what `bestSet(exerciseID:)` says of it, and one with none has no key.
    static func bestSets(_ stores: HistoryStores) async throws -> String? {
        let stats = stores.stats
        let empty = try await stats.bestSets()
        try await stores.materialize(Seeders.workout(number: 0, endedAt: day(-7), [
            Seeders.ExerciseLog(bench, [.init(200, 2), .init(250, 1, .drop), .init(240, 2, .warmup)]),
            .straight(row, sets: 3, reps: 8, pounds: 300),
            Seeders.ExerciseLog(Workouts.exercises[3], [.init(95, 5, .warmup)])
        ]))
        try await stores.materialize(Seeders.workout(number: 1, endedAt: now, [
            Seeders.ExerciseLog(bench, [.init(180, 5), .init(200, 3, .added), .init(225, 1, done: false)]),
            Seeders.ExerciseLog(row, [.init(300, 10), .init(290, 12)])
        ]))
        let deleted = Seeders.workout(number: 2, endedAt: day(-3), [.straight(squat, sets: 3, reps: 5, pounds: 315)])
        try await stores.materialize(deleted)
        try await stores.workouts.delete(id: deleted.id)
        let all = try await stats.bestSets()
        var differences: [String] = []
        for exercise in Workouts.exercises {
            let one = try await stats.bestSet(exerciseID: exercise.id).map { BestSet(weight: $0.weight, reps: $0.reps) }
            if all[exercise.id] != one {
                let batch = String(describing: all[exercise.id])
                differences.append("\(exercise.name): bestSets \(batch), bestSet \(String(describing: one))")
            }
        }
        return ContractCheck.first(
            ContractCheck.expect(empty, [:], "bestSets of an empty history"),
            ContractCheck.expect(all[bench.id], BestSet(weight: .pounds(200), reps: Reps(clamping: 3)), "bench's best"),
            ContractCheck.expect(
                all[row.id],
                BestSet(weight: .pounds(300), reps: Reps(clamping: 10)),
                "the row's best"
            ),
            ContractCheck.expect(Set(all.keys), [bench.id, row.id], "the exercises with a best"),
            ContractCheck.expect(differences, [], "bestSets against bestSet(exerciseID:)")
        )
    }

    /// F12 S2, N9: the sessions of one exercise, and `ExerciseHistory.make`'s fold of them against the queries it
    /// replaces on the history screen. Bench is logged:
    /// - 50 days ago, 175 × 6 after a warm-up;
    /// - 20 days ago in a deload, 150 × 5 three times;
    /// - 10 days ago in two rows around a row of the row: 170 × 5, 225 × 1 left undone and a 200 × 2 drop set,
    ///   then 180 × 3 added;
    /// - now, twice in workouts that started together: warm-ups only, and 185 × 5;
    /// - 3 days ago, in a workout that is then deleted.
    static func exerciseSessions(_ stores: HistoryStores) async throws -> String? {
        let stats = stores.stats
        let empty = try await stats.exerciseSessions(exerciseID: bench.id)
        let workouts = sessionWorkouts
        for workout in workouts {
            try await stores.materialize(workout)
        }
        let deleted = Seeders.workout(number: 5, endedAt: day(-3), [.straight(bench, sets: 1, reps: 1, pounds: 300)])
        try await stores.materialize(deleted)
        try await stores.workouts.delete(id: deleted.id)
        let sessions = try await stats.exerciseSessions(exerciseID: bench.id)
        // Newest first; of the two that started together, the smaller id first.
        let order = [3, 4, 2, 1, 0]
        let drawn = sessions.map { session in session.sets.map { "\($0.weight.formatted(in: .lb))x\($0.reps.value)" } }
        var folds: [String] = []
        for exercise in Workouts.exercises {
            if let difference = try await foldDifference(exercise, stores) {
                folds.append(difference)
            }
        }
        return ContractCheck.first(
            ContractCheck.expect(empty, [], "the sessions of an empty history"),
            ContractCheck.expect(sessions.map(\.workoutID), order.map(Seeders.workoutID), "the sessions' order"),
            ContractCheck.expect(sessions.map(\.startedAt), order.map { workouts[$0].startedAt }, "the dates"),
            ContractCheck.expect(
                drawn,
                [["95x5"], ["185x5"], ["170x5", "200x2", "180x3"], ["150x5", "150x5", "150x5"], ["95x5", "175x6"]],
                "each session's done sets, in row order"
            ),
            ContractCheck.expect(folds, [], "the fold against the queries")
        )
    }

    /// The workouts of the `exerciseSessions` clause, as its comment lists them, but the deleted one.
    private static var sessionWorkouts: [WorkoutState] {
        [
            Seeders.workout(number: 0, endedAt: day(-50), [
                Seeders.ExerciseLog(bench, [.init(95, 5, .warmup), .init(175, 6)]),
                .straight(row, sets: 2, reps: 8, pounds: 200)
            ]),
            Seeders.workout(number: 1, endedAt: day(-20), isDeload: true, [
                .straight(bench, sets: 3, reps: 5, pounds: 150)
            ]),
            Seeders.workout(number: 2, endedAt: day(-10), [
                Seeders.ExerciseLog(bench, [.init(170, 5), .init(225, 1, done: false), .init(200, 2, .drop)]),
                .straight(row, sets: 1, reps: 10, pounds: 210),
                Seeders.ExerciseLog(bench, [.init(180, 3, .added)])
            ]),
            Seeders.workout(number: 3, endedAt: now, [Seeders.ExerciseLog(bench, [.init(95, 5, .warmup)])]),
            Seeders.workout(number: 4, endedAt: now, [.straight(bench, sets: 1, reps: 5, pounds: 185)])
        ]
    }

    /// What `ExerciseHistory.make` of `exercise`'s sessions says that the queries it replaces do not, or nil.
    private static func foldDifference(_ exercise: Exercise, _ stores: HistoryStores) async throws -> String? {
        let stats = stores.stats
        let calendar = try calendar
        let history = try await ExerciseHistory.make(
            sessions: stats.exerciseSessions(exerciseID: exercise.id),
            records: [],
            now: now,
            calendar: calendar
        )
        let weeks = Dictionary(history.weeks.compactMap { week in
            week.e1RM.map { (calendar.isoWeekKey(for: week.start), $0) }
        }) { first, _ in first }
        let best = try await stats.bestSet(exerciseID: exercise.id).map { BestSet(weight: $0.weight, reps: $0.reps) }
        let queried = try await (
            e1RM: stats.bestE1RM(exerciseID: exercise.id),
            sessions: stats.sessionCount(exerciseID: exercise.id),
            weeks: stats.e1RMByWeek(exerciseID: exercise.id, lastWeeks: ExerciseHistory.chartWeeks, calendar: calendar)
        )
        guard history.e1RM == queried.e1RM, history.bestSet == best, history.sessions == queried.sessions,
              weeks == queried.weeks
        else {
            return "\(exercise.name): fold \(history.e1RM as Any), \(history.bestSet as Any), \(history.sessions), "
                + "\(weeks); queries \(queried.e1RM as Any), \(best as Any), \(queried.sessions), \(queried.weeks)"
        }
        return nil
    }
}
