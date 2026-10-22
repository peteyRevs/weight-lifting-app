import Foundation
import LedgerDomain

/// `StatsQueries`' contract as named clauses (F05 S3), over workouts materialised through the
/// `WorkoutRepository` beside it: criterion 4's "Last" line, the bests, criterion 5's e1RM by week,
/// criterion 6's weekly volume, session counts, personal records and the recently logged exercises. The
/// rules a fake must share:
/// - only done sets of stored (finished, not deleted) workouts count;
/// - a workout's date is when it started (product decision #26): a session begun at 23:30 and finished after
///   midnight is the earlier day's, and that week's;
/// - the "Last" line counts `.working` sets, the bests `.working` and `.added` ones (product decision #25), and volume
///   every kind (rule 34).
public enum StatsQueriesContract {
    public typealias Clause = ContractClause<HistoryStores>
    typealias Workouts = WorkoutRepositoryContract

    public static let clauses: [Clause] = [
        Clause("an empty history gives nil, zero or nothing from every query", emptyHistory),
        Clause("lastPerformance is the latest workout's done working sets: 34 bench sessions", lastPerformance),
        Clause("bestSet is the heaviest record set, then more reps; bestE1RM the best estimate up to 12 reps", bests),
        Clause("e1RMByWeek is each week's best estimate over the last 8 weeks; empty weeks are absent", e1RMByWeek),
        Clause("weeklyVolume is Σ weight × reps of done sets of every kind, week by week", weeklyVolume),
        Clause("sessionsCompleted counts workouts started in the range; sessionCount those with a done set", sessions),
        Clause(
            "personalRecords lists the records detected against the bests before each workout, newest first",
            personalRecords
        ),
        Clause("bests(before:for:) count the record sets of the workouts before one, by start then id", bestsBefore),
        Clause("recentlyLogged lists exercises by their latest workout, newest first, up to the limit", recentlyLogged),
        Clause("bestSets is bestSet of every exercise in one read; one with no counted set has no entry", bestSets),
        Clause(
            "exerciseSessions lists each workout's done sets, newest first; its fold is the bests, weeks and count",
            exerciseSessions
        ),
        Clause("every query follows updateSets and delete", followsEdits)
    ]

    // MARK: Fixtures

    /// The current time of the contract's stats: Wednesday 2026-09-16T05:20:00Z.
    public static let now = EventBuilders.start

    /// Stats weeks starting on Monday, in UTC (decision #15 with a Monday start is the ISO week).
    public static var calendar: WeekCalendar {
        get throws {
            try calendar(weekStart: .monday)
        }
    }

    /// Stats weeks starting on `weekStart`, in UTC.
    public static func calendar(weekStart: Weekday) throws -> WeekCalendar {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try timeZone
        return try WeekCalendar(startDate: blockStart, weekStart: weekStart, calendar: utc)
    }

    static let bench = Workouts.exercises[0]
    static let row = Workouts.exercises[1]
    static let squat = Workouts.exercises[2]

    /// `days` whole days from `now`, at the same time of day.
    static func day(_ days: Int) -> Date {
        now.addingTimeInterval(86400 * Double(days))
    }

    /// The Brzycki estimate of `reps` × `pounds` lb (decision #4), or `nil` above 12 reps.
    public static func e1RM(_ pounds: Decimal, _ reps: Int) -> Weight? {
        OneRepMax.brzycki(weight: .pounds(pounds), reps: Reps(clamping: reps))
    }

    private static var timeZone: TimeZone {
        get throws {
            guard let utc = TimeZone(secondsFromGMT: 0) else {
                throw Seeders.UnsupportedShape(parameter: "secondsFromGMT", value: 0)
            }
            return utc
        }
    }

    private static var blockStart: CivilDate {
        get throws {
            guard let start = CivilDate(year: 2026, month: 8, day: 17) else {
                throw Seeders.UnsupportedShape(parameter: "blockStart", value: 2026)
            }
            return start
        }
    }

    // MARK: Clauses

    static func emptyHistory(_ stores: HistoryStores) async throws -> String? {
        let stats = stores.stats
        let week = try calendar.week(containing: now)
        let best = try await stats.bestSet(exerciseID: bench.id)
        return try await ContractCheck.first(
            ContractCheck.expect(stats.lastPerformance(exerciseID: bench.id), nil, "lastPerformance"),
            ContractCheck.expect(best?.weight, nil, "bestSet"),
            ContractCheck.expect(stats.bestE1RM(exerciseID: bench.id), nil, "bestE1RM"),
            ContractCheck.expect(
                stats.e1RMByWeek(exerciseID: bench.id, lastWeeks: 8, calendar: calendar),
                [:],
                "e1RMByWeek"
            ),
            ContractCheck.expect(stats.weeklyVolume(in: week), .zero, "weeklyVolume"),
            ContractCheck.expect(stats.sessionsCompleted(in: week), 0, "sessionsCompleted"),
            ContractCheck.expect(stats.sessionCount(exerciseID: bench.id), 0, "sessionCount"),
            ContractCheck.expect(stats.personalRecords(exerciseID: bench.id), [], "personalRecords"),
            ContractCheck.expect(stats.recentlyLogged(limit: 5), [], "recentlyLogged")
        )
    }

    /// Criterion 4. 34 bench sessions two days apart, the last ending at `now` after an hour: a 180 × 4, a
    /// 175 × 5, three sets of 180 × 5, a 185 left undone, a done drop set and a done added set. The "Last" line
    /// counts the five done working sets and shows the heaviest of them with the most reps, which is not the
    /// first, dated when the workout **started** (product decision #26).
    /// - A workout that started at the same instant, stored first and with the larger id, does not replace it:
    ///   of two workouts starting together, the one with the smaller id is the latest.
    /// - A long workout that started earlier but ended later does not replace it: the latest is the last started.
    /// - A later workout in which bench was not done as a working set does not replace it either.
    /// - Deleting the 34th falls back to the workout that started with it.
    static func lastPerformance(_ stores: HistoryStores) async throws -> String? {
        try await materializeBenchSessions(33, in: stores)
        try await stores.materialize(Seeders.workout(number: 35, endedAt: now, [
            .straight(bench, sets: 4, reps: 6, pounds: 170)
        ]))
        try await stores.materialize(Seeders.workout(number: 36, endedAt: now.addingTimeInterval(1800), minutes: 180, [
            .straight(bench, sets: 3, reps: 5, pounds: 150)
        ]))
        let last = Seeders.workout(number: 33, endedAt: now, [
            Seeders.ExerciseLog(bench, [
                .init(180, 4), .init(175, 5), .init(180, 5), .init(180, 5), .init(180, 5),
                .init(185, 5, done: false), .init(155, 8, .drop), .init(200, 3, .added)
            ]),
            .straight(row, sets: 3, reps: 8, pounds: 70)
        ])
        try await stores.materialize(last)
        try await stores.materialize(Seeders.workout(number: 34, endedAt: day(1), [
            Seeders.ExerciseLog(bench, [.init(185, 5, done: false), .init(150, 5, .warmup)]),
            .straight(row, sets: 3, reps: 8, pounds: 75)
        ]))
        let stats = stores.stats
        let line = try await stats.lastPerformance(exerciseID: bench.id)
        let sessions = try await stats.sessionCount(exerciseID: bench.id)
        let unknown = try await stats.lastPerformance(exerciseID: Workouts.exercises[5].id)
        try await stores.workouts.delete(id: last.id)
        let afterDelete = try await stats.lastPerformance(exerciseID: bench.id)
        let started = now.addingTimeInterval(-3600)
        let twin = LastPerformance(date: started, sets: 4, reps: 6, load: .pounds(170))
        return ContractCheck.first(
            ContractCheck.expect(
                line,
                LastPerformance(date: started, sets: 5, reps: 5, load: .pounds(180)),
                "the Last line"
            ),
            ContractCheck.expect(sessions, 37, "sessionCount: 36 sessions and one with a done warm-up"),
            ContractCheck.expect(unknown, nil, "lastPerformance of an exercise never logged"),
            ContractCheck.expect(afterDelete, twin, "lastPerformance after the 34th was deleted")
        )
    }

    /// Bench sessions 0 to `count` − 1, two days apart, the last two days before `now`: 5 × 5 at a load that
    /// rises 5 lb every other session.
    private static func materializeBenchSessions(_ count: Int, in stores: HistoryStores) async throws {
        for session in 0 ..< count {
            let pounds = Decimal(100 + 5 * (session / 2))
            try await stores.materialize(Seeders.workout(number: session, endedAt: day(2 * (session - count)), [
                .straight(bench, sets: 5, reps: 5, pounds: pounds)
            ]))
        }
    }

    /// The bests count done `.working` and `.added` sets, and no other kind.
    /// - The heaviest set is 200 × 3 (added), over a 200 × 2, a heavier undone set, and a heavier drop set and
    ///   warm-up.
    /// - The best estimate is 185 × 8, over the heavier 200 × 3, a 150 × 20 (no estimate above 12 reps), and the
    ///   drop set and the warm-up, whose estimates are both higher.
    static func bests(_ stores: HistoryStores) async throws -> String? {
        try await stores.materialize(Seeders.workout(number: 0, endedAt: day(-7), [
            Seeders.ExerciseLog(bench, [
                .init(185, 8), .init(200, 2), .init(150, 20), .init(250, 1, .drop), .init(240, 2, .warmup)
            ]),
            .straight(row, sets: 3, reps: 8, pounds: 300)
        ]))
        try await stores.materialize(Seeders.workout(number: 1, endedAt: now, [
            Seeders.ExerciseLog(bench, [.init(180, 5), .init(200, 3, .added), .init(225, 1, done: false)])
        ]))
        let best = try await stores.stats.bestSet(exerciseID: bench.id)
        return try await ContractCheck.first(
            ContractCheck.expect(best?.weight, .pounds(200), "bestSet's weight"),
            ContractCheck.expect(best?.reps.value, 3, "bestSet's reps"),
            ContractCheck.expect(stores.stats.bestE1RM(exerciseID: bench.id), e1RM(185, 8), "bestE1RM")
        )
    }
}
