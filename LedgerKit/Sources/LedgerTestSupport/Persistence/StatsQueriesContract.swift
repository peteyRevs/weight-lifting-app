import Foundation
import LedgerDomain

/// `StatsQueries`' contract as named clauses (F05 S3), over workouts materialised through the
/// `WorkoutRepository` beside it: criterion 4's "Last" line, the bests, criterion 5's e1RM by week,
/// criterion 6's weekly volume, session counts, personal records and the recently logged exercises. The
/// rules a fake must share:
/// - only done sets of stored (finished, not deleted) workouts count;
/// - a workout's date is when it ended;
/// - the "Last" line counts `.working` sets, the bests `.working` and `.added` ones (decision #3), and volume
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
        Clause("sessionsCompleted counts workouts ended in the range; sessionCount those with a done set", sessions),
        Clause("personalRecords lists an exercise's records newest first, and follows its workouts", personalRecords),
        Clause("recentlyLogged lists exercises by their latest workout, newest first, up to the limit", recentlyLogged),
        Clause("every query follows updateSets and delete", followsEdits)
    ]

    // MARK: Fixtures

    /// The current time of the contract's stats: Wednesday 2026-09-16T05:20:00Z.
    public static let now = EventBuilders.start

    /// Stats weeks starting on Monday, in UTC (decision #15 with a Monday start is the ISO week).
    public static var calendar: WeekCalendar {
        get throws {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = try timeZone
            return try WeekCalendar(startDate: blockStart, weekStart: .monday, calendar: utc)
        }
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

    /// Criterion 4. 34 bench sessions two days apart, the last ending at `now`: four sets of 180 × 5, one of
    /// 180 × 4, a 185 left undone, a done drop set and a done added set. The "Last" line counts the five done
    /// working sets and shows the heaviest of them with the most reps. A later workout in which bench was not
    /// done does not replace it; deleting the 34th falls back to the 33rd.
    static func lastPerformance(_ stores: HistoryStores) async throws -> String? {
        for session in 0 ..< 33 {
            let pounds = Decimal(100 + 5 * (session / 2))
            try await stores.materialize(Seeders.workout(number: session, endedAt: day(2 * (session - 33)), [
                .straight(bench, sets: 5, reps: 5, pounds: pounds)
            ]))
        }
        let last = Seeders.workout(number: 33, endedAt: now, [
            Seeders.ExerciseLog(bench, [
                .init(180, 5), .init(180, 5), .init(180, 4), .init(180, 5), .init(180, 5),
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
        return try await ContractCheck.first(
            ContractCheck.expect(
                line,
                LastPerformance(date: now, sets: 5, reps: 5, load: .pounds(180)),
                "lastPerformance after 34 sessions"
            ),
            ContractCheck.expect(sessions, 35, "sessionCount: 34 sessions and one with a done warm-up"),
            ContractCheck.expect(unknown, nil, "lastPerformance of an exercise never logged"),
            ContractCheck.expect(
                stats.lastPerformance(exerciseID: bench.id),
                LastPerformance(date: day(-2), sets: 5, reps: 5, load: .pounds(180)),
                "lastPerformance after the 34th was deleted"
            )
        )
    }

    /// The bests count done `.working` and `.added` sets. The heaviest set is 200 × 3 (added), over a heavier
    /// drop set, a heavier undone set and a 200 × 2. The best estimate is 185 × 8, over the heavier 200 × 3 and
    /// over a 150 × 20, which has no estimate.
    static func bests(_ stores: HistoryStores) async throws -> String? {
        try await stores.materialize(Seeders.workout(number: 0, endedAt: day(-7), [
            Seeders.ExerciseLog(bench, [.init(185, 8), .init(200, 2), .init(150, 20), .init(210, 1, .drop)]),
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
