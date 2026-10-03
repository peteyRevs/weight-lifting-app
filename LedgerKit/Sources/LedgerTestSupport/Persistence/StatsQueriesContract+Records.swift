import Foundation
import LedgerDomain
import LedgerPersistence

/// Personal records and the bests before a workout (product decision #27). A store never takes records from its
/// caller: after every write they are `PersonalRecords.detect` replayed over history in order (by start, then
/// id), each workout judged against the bests before it, with `achievedAt` its start. So a fake that judges a
/// workout against the all-time bests (itself included, or every other workout), or that stores a workout's
/// records once and never revisits them when an earlier workout changes, breaks these clauses.
extension StatsQueriesContract {
    /// Workout `number`, started at `start` and an hour long.
    static func session(
        _ number: Int,
        startedAt start: Date,
        isDeload: Bool = false,
        _ exercises: [Seeders.ExerciseLog]
    ) -> WorkoutState {
        Seeders.workout(
            number: number,
            endedAt: Workouts.ending(startedAt: start),
            isDeload: isDeload,
            exercises
        )
    }

    /// The record `kind`, beating `previous`, that `exercise` set in `workout`: achieved at its start.
    static func record(
        _ exercise: Exercise,
        _ kind: PRKind,
        over previous: PRKind,
        in workout: WorkoutState
    ) -> PersonalRecord {
        PersonalRecord(
            exerciseID: exercise.id,
            kind: kind,
            previous: previous,
            achievedAt: workout.startedAt,
            workoutID: workout.id
        )
    }

    /// The estimated 1RM of `reps` × `pounds` lb, as a record kind.
    static func estimate(_ pounds: Decimal, _ reps: Int) -> PRKind {
        .estimatedOneRepMax(e1RM(pounds, reps) ?? .zero)
    }

    /// `pounds` lb for `reps`, as a record kind.
    static func weight(_ pounds: Decimal, _ reps: Int) -> PRKind {
        .weightAtReps(.pounds(pounds), Reps(clamping: reps))
    }

    /// `personalRecords`' history, oldest first. Bench: a baseline (its warm-up and drop set count for nothing);
    /// an estimate and a weight record; a weight record at 3 reps (220 lb over 210 × 5); a deload of 250 × 5,
    /// which sets none but counts; and 255 × 3 over it. Squat: two workouts that start together, judged in id
    /// order, so the second holds both records. Row: a baseline at 8 reps, then both records.
    struct RecordHistory {
        let first = session(0, startedAt: day(-6), [Seeders.ExerciseLog(bench, [
            .init(200, 5), .init(200, 5), .init(300, 1, .warmup), .init(290, 2, .drop)
        ])])
        let second = session(1, startedAt: day(-5), [
            .straight(bench, sets: 2, reps: 5, pounds: 210), .straight(row, sets: 3, reps: 8, pounds: 60)
        ])
        let third = session(2, startedAt: day(-3), [
            Seeders.ExerciseLog(bench, [.init(205, 5), .init(220, 3)]), .straight(squat, sets: 3, reps: 5, pounds: 100)
        ])
        let twin = session(3, startedAt: day(-3), [.straight(squat, sets: 3, reps: 5, pounds: 110)])
        let deload = session(4, startedAt: day(-2), isDeload: true, [.straight(bench, sets: 3, reps: 5, pounds: 250)])
        let last = session(5, startedAt: day(-1), [
            .straight(bench, sets: 1, reps: 3, pounds: 255), .straight(row, sets: 3, reps: 8, pounds: 65)
        ])
    }

    /// `RecordHistory` stored newest first, so each workout stored lands before every stored one and the records
    /// of those after it must follow; then its second workout deleted.
    static func personalRecords(_ stores: HistoryStores) async throws -> String? {
        let history = RecordHistory()
        let (second, third, twin, last) = (history.second, history.third, history.twin, history.last)
        for workout in [last, history.deload, twin, third, second, history.first] {
            try await stores.materialize(workout)
        }
        let stats = stores.stats
        let benches = try await stats.personalRecords(exerciseID: bench.id)
        let squats = try await stats.personalRecords(exerciseID: squat.id)
        let rows = try await stats.personalRecords(exerciseID: row.id)
        try await stores.workouts.delete(id: second.id)
        let newest = record(bench, weight(255, 3), over: weight(250, 5), in: last)
        return try await ContractCheck.first(
            ContractCheck.expect(benches, [
                newest,
                record(bench, weight(220, 3), over: weight(210, 5), in: third),
                record(bench, estimate(210, 5), over: estimate(200, 5), in: second),
                record(bench, weight(210, 5), over: weight(200, 5), in: second)
            ], "bench records, newest first"),
            ContractCheck.expect(squats, [
                record(squat, estimate(110, 5), over: estimate(100, 5), in: twin),
                record(squat, weight(110, 5), over: weight(100, 5), in: twin)
            ], "squat records: of two workouts that start together, the smaller id first"),
            ContractCheck.expect(rows, [
                record(row, estimate(65, 8), over: estimate(60, 8), in: last),
                record(row, weight(65, 8), over: weight(60, 8), in: last)
            ], "row records"),
            ContractCheck.expect(stats.personalRecords(exerciseID: bench.id), [
                newest,
                record(bench, estimate(220, 3), over: estimate(200, 5), in: third),
                record(bench, weight(220, 3), over: weight(200, 5), in: third)
            ], "bench records after the second workout is deleted"),
            ContractCheck.expect(stats.personalRecords(exerciseID: row.id), [], "row records after that delete")
        )
    }

    /// The bests before the third workout of `bestsBefore`: the first's 200 × 5 and 180 × 8 and the second's
    /// added 210 × 3, and its row at 15 reps (no estimate).
    static var bestsBeforeThird: PersonalRecords.Bests {
        PersonalRecords.Bests(
            e1RM: [bench.id: e1RM(200, 5) ?? .zero],
            weightAtReps: [
                bench.id: [
                    Reps(clamping: 5): .pounds(200), Reps(clamping: 8): .pounds(180), Reps(clamping: 3): .pounds(210)
                ],
                row.id: [Reps(clamping: 15): .pounds(60)]
            ]
        )
    }

    /// The bests before a workout count the done working and added sets of the stored workouts that start
    /// before it, or with it and a smaller id: never the workout itself, a deleted workout, a warm-up, a drop or
    /// an undone set. The workout need not be stored: a live one is judged the same way.
    static func bestsBefore(_ stores: HistoryStores) async throws -> String? {
        let first = session(0, startedAt: day(-6), [Seeders.ExerciseLog(bench, [
            .init(200, 5), .init(180, 8), .init(300, 1, .warmup), .init(290, 2, .drop), .init(240, 3, done: false)
        ])])
        let second = session(1, startedAt: day(-4), [
            Seeders.ExerciseLog(bench, [.init(210, 3, .added)]), .straight(row, sets: 2, reps: 15, pounds: 60)
        ])
        let gone = session(2, startedAt: day(-5), [.straight(bench, sets: 1, reps: 5, pounds: 400)])
        let third = session(3, startedAt: day(-2), [.straight(bench, sets: 2, reps: 5, pounds: 220)])
        let twin = session(4, startedAt: day(-2), [.straight(bench, sets: 1, reps: 5, pounds: 230)])
        for workout in [twin, third, gone, second, first] {
            try await stores.materialize(workout)
        }
        try await stores.workouts.delete(id: gone.id)
        var live = session(9, startedAt: day(-3), [.straight(bench, sets: 1, reps: 5, pounds: 500)])
        live.phase = .live
        live.endedAt = nil
        var beforeTwin = bestsBeforeThird
        beforeTwin.e1RM[bench.id] = e1RM(220, 5)
        beforeTwin.weightAtReps[bench.id]?[Reps(clamping: 5)] = .pounds(220)
        let (all, none, stats) = (Set([bench.id, row.id, squat.id]), PersonalRecords.Bests(), stores.stats)
        let rowOnly = PersonalRecords.Bests(weightAtReps: [row.id: [Reps(clamping: 15): .pounds(60)]])
        return try await ContractCheck.first(
            ContractCheck.expect(stats.bests(before: third, for: all), bestsBeforeThird, "before the third workout"),
            ContractCheck.expect(stats.bests(before: twin, for: all), beforeTwin, "before its twin, a larger id"),
            ContractCheck.expect(stats.bests(before: live, for: all), bestsBeforeThird, "before a live workout"),
            ContractCheck.expect(stats.bests(before: first, for: all), none, "before the first"),
            ContractCheck.expect(stats.bests(before: twin, for: []), none, "for no exercise"),
            ContractCheck.expect(stats.bests(before: third, for: [row.id]), rowOnly, "for the row only")
        )
    }
}

/// Personal records after an edit (product decision #27).
extension WorkoutRepositoryContract {
    /// The two bench records `pounds` × 5 sets in `workout` over `over` × 5.
    static func benchRecords(_ pounds: Decimal, over: Decimal, in workout: WorkoutState) -> [PersonalRecord] {
        typealias Stats = StatsQueriesContract
        return [
            Stats.record(exercises[0], Stats.estimate(pounds, 5), over: Stats.estimate(over, 5), in: workout),
            Stats.record(exercises[0], Stats.weight(pounds, 5), over: Stats.weight(over, 5), in: workout)
        ]
    }

    /// Bench 200 × 5, then 2,250 × 5 (a typo for 225), then 230 × 5, two days apart.
    struct TypoHistory {
        let first = StatsQueriesContract.session(0, startedAt: StatsQueriesContract.day(-6), [
            .straight(exercises[0], sets: 3, reps: 5, pounds: 200)
        ])
        let typo = StatsQueriesContract.session(1, startedAt: StatsQueriesContract.day(-4), [
            Seeders.ExerciseLog(exercises[0], [.init(2250, 5), .init(200, 5)])
        ])
        let last = StatsQueriesContract.session(2, startedAt: StatsQueriesContract.day(-2), [
            .straight(exercises[0], sets: 3, reps: 5, pounds: 230)
        ])
    }

    /// The typo case. Bench 200 × 5, then 2,250 × 5 (a typo for 225), then 230 × 5. While the typo stands the
    /// middle workout holds both records and the last none; corrected, both hold them; lowered below the first,
    /// only the last does, over 200; with the first deleted, over the middle's 195; and a rebuild of the middle
    /// with the typo brings the first state back.
    static func recordsFollowEdits(_ stores: HistoryStores) async throws -> String? {
        let history = TypoHistory()
        let (first, typo, last) = (history.first, history.typo, history.last)
        for workout in [first, typo, last] {
            try await stores.materialize(workout)
        }
        let records = { try await stores.stats.personalRecords(exerciseID: exercises[0].id) }
        let edit = { (pounds: [Decimal]) in
            var sets = typo.exercises[0].sets
            for (index, weight) in pounds.enumerated() {
                sets[index].weight = .pounds(weight)
            }
            try await stores.workouts.updateSets(workoutExerciseID: typo.exercises[0].id, sets: sets)
        }
        let withTypo = try await records()
        try await edit([225])
        let corrected = try await records()
        try await edit([195, 190])
        let lowered = try await records()
        try await stores.workouts.delete(id: first.id)
        let withoutFirst = try await records()
        try await stores.materialize(first)
        let restored = try await records()
        try await stores.materialize(typo)
        let typoRecords = benchRecords(2250, over: 200, in: typo)
        return try await ContractCheck.first(
            ContractCheck.expect(withTypo, typoRecords, "with the typo: the middle's records, the last none"),
            ContractCheck.expect(
                corrected,
                benchRecords(230, over: 225, in: last) + benchRecords(225, over: 200, in: typo),
                "after correcting it to 225"
            ),
            ContractCheck.expect(lowered, benchRecords(230, over: 200, in: last), "after lowering it below the first"),
            ContractCheck.expect(withoutFirst, benchRecords(230, over: 195, in: last), "after deleting the first"),
            ContractCheck.expect(
                restored,
                benchRecords(230, over: 200, in: last),
                "after materialising the first again"
            ),
            ContractCheck.expect(records(), typoRecords, "after a rebuild of the middle with the typo")
        )
    }
}
