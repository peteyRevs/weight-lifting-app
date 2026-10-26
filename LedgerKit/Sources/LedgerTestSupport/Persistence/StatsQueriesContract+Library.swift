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

    /// F12 S2 (finding F12-S2-3): the sessions observed follow a workout of the exercise finished, edited or deleted
    /// behind the newest one, and a write of another exercise alone emits nothing: every value is read as it comes,
    /// and a read after such a write must wait out `quiet` (finding F12-S2-R1-6).
    static func observeExerciseSessions(_ stores: HistoryStores) async throws -> String? {
        let stats = stores.stats
        let newest = Seeders.workout(number: 1, endedAt: now, [.straight(bench, sets: 1, reps: 5, pounds: 185)])
        let older = Seeders.workout(number: 2, endedAt: day(-10), [.straight(bench, sets: 2, reps: 5, pounds: 175)])
        let rows = Seeders.workout(number: 3, endedAt: day(-5), [.straight(row, sets: 2, reps: 8, pounds: 200)])
        let values = StreamArrivals(stats.observeExerciseSessions(exerciseID: bench.id))
        defer { values.cancel() }
        let initial = await values.next()
        try await stores.materialize(newest)
        let afterNewest = await values.next()
        try await stores.materialize(rows)
        let afterRows = await values.next(within: quiet)
        try await stores.materialize(older)
        let afterOlder = await values.next()
        var edited = older.exercises[0]
        edited.sets.removeLast()
        try await stores.workouts.updateSets(workoutExerciseID: edited.id, sets: edited.sets)
        let afterEdit = await values.next()
        try await stores.workouts.updateSets(workoutExerciseID: rows.exercises[0].id, sets: [])
        let afterRowEdit = await values.next(within: quiet)
        try await stores.workouts.delete(id: older.id)
        let afterDelete = await values.next()
        let drawn = { (sessions: [ExerciseSession]?) in sessions?.map { "\($0.sets.count)" } ?? ["ended"] }
        let read = try await stats.exerciseSessions(exerciseID: bench.id)
        return ContractCheck.first(
            ContractCheck.expect(drawn(initial), [], "the first value"),
            ContractCheck.expect(afterNewest?.map(\.workoutID), [newest.id], "the value after the newest workout"),
            ContractCheck.expect(afterRows.map(drawn), nil, "a value after the row's workout, which is unheard"),
            ContractCheck.expect(drawn(afterOlder), ["1", "2"], "the value after an older workout"),
            ContractCheck.expect(drawn(afterEdit), ["1", "1"], "the value after updateSets of the older workout"),
            ContractCheck.expect(afterRowEdit.map(drawn), nil, "a value after the row's edit, which is unheard"),
            ContractCheck.expect(afterDelete, read, "the value after delete of the older one"),
            ContractCheck.expect(read.map(\.workoutID), [newest.id], "the sessions left")
        )
    }

    /// F12 S3, N20: the Library's stats observed follow a workout finished, edited or deleted, the newest or an older
    /// one, and a write that changes none of them (a workout with nothing done) emits nothing. Each value is what
    /// `recentlyLogged`, `sessionCount` and `bestSets` read at that moment; the limit is 2, so a third exercise
    /// logged earlier than the other two is not recent, though it has a best.
    static func observeLibraryStats(_ stores: HistoryStores) async throws -> String? {
        let stats = stores.stats
        let seen = try await libraryArrivals(stores)
        let read = try await LibraryStats(
            recent: stats.recentlyLogged(limit: 2),
            sessions: [
                bench.id: stats.sessionCount(exerciseID: bench.id),
                row.id: stats.sessionCount(exerciseID: row.id)
            ],
            bestSets: stats.bestSets()
        )
        let best = { (stats: LibraryStats?, exercise: Exercise) in
            stats?.bestSets[exercise.id].map { "\($0.weight.formatted(in: .lb))x\($0.reps.value)" } ?? "none"
        }
        return ContractCheck.first(
            ContractCheck.expect(seen.initial, LibraryStats(recent: [], sessions: [:], bestSets: [:]), "the first"),
            ContractCheck.expect(seen.newest?.recent, [bench.id], "recent after the newest workout"),
            ContractCheck.expect(seen.newest?.sessions, [bench.id: 1], "sessions after the newest workout"),
            ContractCheck.expect(seen.older?.recent, [bench.id, row.id], "recent after an older workout"),
            ContractCheck.expect(seen.older?.sessions, [bench.id: 2, row.id: 1], "sessions after an older workout"),
            ContractCheck.expect(best(seen.oldest, squat), "225x5", "the oldest workout's best, though not recent"),
            ContractCheck.expect(seen.oldest?.recent, [bench.id, row.id], "recent after the oldest workout"),
            ContractCheck.expect(seen.undone.map { _ in "a value" }, nil, "a value after a workout with nothing done"),
            ContractCheck.expect(best(seen.edit, row), "210x8", "the row's best after updateSets of an older workout"),
            // Both are now last logged in the older workout: of one workout, in id order (`recentlyLogged`).
            ContractCheck.expect(seen.delete.map { Set($0.recent) }, [bench.id, row.id], "recent after the delete"),
            ContractCheck.expect(best(seen.delete, bench), "175x5", "bench's best after the newest is deleted"),
            ContractCheck.expect(seen.delete, read, "the value after delete, against the reads")
        )
    }

    /// What `observeLibraryStats(recentLimit: 2)` emits at each write of its clause; `undone` must be nil.
    private struct LibraryArrivals {
        var initial, newest, older, oldest, undone, edit, delete: LibraryStats?
    }

    /// Writes the clause's history one step at a time, reading the value each step brings.
    private static func libraryArrivals(_ stores: HistoryStores) async throws -> LibraryArrivals {
        let newest = Seeders.workout(number: 1, endedAt: now, [.straight(bench, sets: 1, reps: 5, pounds: 185)])
        let older = Seeders.workout(number: 2, endedAt: day(-10), [
            .straight(row, sets: 2, reps: 8, pounds: 200),
            .straight(bench, sets: 1, reps: 5, pounds: 175)
        ])
        let values = StreamArrivals(stores.stats.observeLibraryStats(recentLimit: 2))
        defer { values.cancel() }
        var seen = LibraryArrivals()
        seen.initial = await values.next()
        try await stores.materialize(newest)
        seen.newest = await values.next()
        try await stores.materialize(older)
        seen.older = await values.next()
        try await stores.materialize(
            Seeders.workout(number: 3, endedAt: day(-20), [.straight(squat, sets: 1, reps: 5, pounds: 225)])
        )
        seen.oldest = await values.next()
        try await stores.materialize(
            Seeders.workout(number: 4, endedAt: day(-5), [Seeders.ExerciseLog(squat, [.init(315, 5, done: false)])])
        )
        seen.undone = await values.next(within: quiet)
        var edited = older.exercises[0]
        edited.sets[0].weight = .pounds(210)
        try await stores.workouts.updateSets(workoutExerciseID: edited.id, sets: edited.sets)
        seen.edit = await values.next()
        try await stores.workouts.delete(id: newest.id)
        seen.delete = await values.next()
        return seen
    }

    /// How long a read waits for a value that must not come (finding F12-S2-R1-6).
    static let quiet: Duration = .milliseconds(200)

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
