import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBStatsQueries`: criteria 4 to 6 through the shared contract, and what only the SQL can get wrong:
/// which rows count, exact volume, and the week a workout falls in.
@Suite("GRDBStatsQueries", .tags(.persistence), .timeLimit(.minutes(1)))
struct StatsQueriesTests {
    typealias Contract = StatsQueriesContract

    static let bench = WorkoutRepositoryContract.exercises[0]

    @Test("The GRDB queries keep the contract clause", arguments: StatsQueriesContract.clauses)
    func contract_clauseHolds(_ clause: StatsQueriesContract.Clause) async throws {
        let issue = try await clause.check(Repositories.withProgramExercises().history)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("A workout that is not finished, and soft-deleted exercise and set rows, count for no query")
    func onlyLiveRowsOfFinishedWorkouts_count() async throws {
        let repositories = try Repositories()
        let now = Contract.now
        let kept = Seeders.workout(number: 0, endedAt: now.addingTimeInterval(-86400), [
            .straight(Self.bench, sets: 3, reps: 5, pounds: 150)
        ])
        let hidden = (1 ... 4).map { number in
            Seeders.workout(number: number, endedAt: now, [.straight(Self.bench, sets: 3, reps: 5, pounds: 200)])
        }
        for workout in [kept] + hidden {
            try await repositories.history.materialize(workout)
        }
        // A foreign writer's discarded workout, a deleted exercise row, deleted set rows, and a workout row
        // deleted on its own (a sync applies a parent's delete before its children's).
        try await repositories.execute("UPDATE workout SET phase = 'discarded' WHERE id = ?", [
            ColumnCodec.text(hidden[0].id)
        ])
        try await repositories.execute("UPDATE workout_exercise SET deleted_at = 'then' WHERE workout_id = ?", [
            ColumnCodec.text(hidden[1].id)
        ])
        try await repositories.execute("UPDATE logged_set SET deleted_at = 'then' WHERE workout_exercise_id = ?", [
            ColumnCodec.text(hidden[2].exercises[0].id)
        ])
        try await repositories.execute("UPDATE workout SET deleted_at = 'then' WHERE id = ?", [
            ColumnCodec.text(hidden[3].id)
        ])
        let stats = repositories.stats
        let week = try Contract.calendar.week(containing: now)
        #expect(try await stats.lastPerformance(exerciseID: Self.bench.id)?.load == .pounds(150))
        #expect(try await stats.bestSet(exerciseID: Self.bench.id)?.weight == .pounds(150))
        #expect(try await stats.bestE1RM(exerciseID: Self.bench.id) == Contract.e1RM(150, 5))
        #expect(try await stats.weeklyVolume(in: week) == kept.volume)
        #expect(try await stats.sessionCount(exerciseID: Self.bench.id) == 1)
        #expect(try await stats.recentlyLogged(limit: 5) == [Self.bench.id])
        // A workout with no done set left is still a session; the discarded and the deleted one are not.
        #expect(try await stats.sessionsCompleted(in: week) == 3)
        // The lists show what the stats count: the discarded and the deleted workout are in neither.
        #expect(try await repositories.workouts.recent(limit: 9).map(\.id) == [hidden[1].id, hidden[2].id, kept.id])
        #expect(try await repositories.workouts.workouts(in: week).count == 3)
        #expect(try await stats.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: 8, calendar: Contract.calendar)
            .count == 1)
    }

    @Test("Volume is exact at any size: 2,000 reps of 185 lb and of 0.01 lb sum with no rounding")
    func weeklyVolume_isExact() async throws {
        let repositories = try Repositories()
        let hundredth = Decimal(string: "0.01") ?? 0
        let workouts = (0 ..< 20).map { number in
            Seeders.workout(number: number, endedAt: Contract.now.addingTimeInterval(Double(number)), [
                .straight(Self.bench, sets: 10, reps: 10, pounds: 185),
                .straight(WorkoutRepositoryContract.exercises[1], sets: 10, reps: 10, pounds: hundredth)
            ])
        }
        for workout in workouts {
            try await repositories.history.materialize(workout)
        }
        let volume = try await repositories.stats.weeklyVolume(in: .distantPast ..< .distantFuture)
        #expect(volume == Volume(gramReps: Weight.pounds(2000 * 185 + 20).grams))
        #expect(volume.formatted(in: .lb) == "370,020")
    }

    @Test("A week follows the calendar's week start and time zone: a Sunday workout moves with a Sunday start")
    func e1RMByWeek_followsTheWeekStart() async throws {
        let repositories = try Repositories()
        // Sunday 2026-09-13T12:00Z, three days before `now` (a Wednesday).
        let sunday = Contract.now.addingTimeInterval(-3 * 86400 + 6 * 3600 + 40 * 60)
        try await repositories.history.materialize(Seeders.workout(number: 0, endedAt: sunday, [
            .straight(Self.bench, sets: 1, reps: 5, pounds: 180)
        ]))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(CivilDate(year: 2026, month: 8, day: 17))
        let monday = WeekCalendar(startDate: start, weekStart: .monday, calendar: utc)
        let sundayStart = WeekCalendar(startDate: start, weekStart: .sunday, calendar: utc)
        let stats = repositories.stats
        #expect(try await stats.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: 1, calendar: monday).isEmpty)
        let thisWeek = try await stats.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: 1, calendar: sundayStart)
        #expect(try thisWeek == [sundayStart.isoWeekKey(for: sunday): #require(Contract.e1RM(180, 5))])
        let twoWeeks = try await stats.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: 2, calendar: monday)
        #expect(twoWeeks.keys.map(\.week) == [monday.isoWeekKey(for: sunday).week])
        // Very many weeks, and a `now` no calendar holds, neither trap nor loop.
        #expect(try await stats.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: .max, calendar: monday).count == 1)
        let never = GRDBStatsQueries(repositories.queue, now: { Date(timeIntervalSinceReferenceDate: .infinity) })
        #expect(try await never.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: 8, calendar: monday).isEmpty)
    }

    @Test("An exercise performed twice in one workout is one session, and its working sets one Last line")
    func exerciseTwiceInAWorkout_isOneSession() async throws {
        let repositories = try Repositories()
        try await repositories.history.materialize(Seeders.workout(number: 0, endedAt: Contract.now, [
            .straight(Self.bench, sets: 2, reps: 5, pounds: 180),
            .straight(WorkoutRepositoryContract.exercises[1], sets: 2, reps: 8, pounds: 70),
            .straight(Self.bench, sets: 1, reps: 3, pounds: 190)
        ]))
        let stats = repositories.stats
        #expect(try await stats.sessionCount(exerciseID: Self.bench.id) == 1)
        #expect(try await stats.lastPerformance(exerciseID: Self.bench.id) == LastPerformance(
            date: Contract.now.addingTimeInterval(-3600), // the workout's start (product decision #26)
            sets: 3,
            reps: 3,
            load: .pounds(190)
        ))
    }

    @Test("A finished row with no end is foreign damage: listed nowhere, counted nowhere, its records hidden")
    func finishedRowWithNoEnd_countsNowhere() async throws {
        let repositories = try Repositories()
        let workout = WorkoutRepositoryContract.workout()
        let records = WorkoutRepositoryTests.records(of: workout)
        try await repositories.history.materialize(workout, prs: records)
        #expect(try await repositories.stats.personalRecords(exerciseID: Self.bench.id) == records)
        try await repositories.execute("UPDATE workout SET ended_at = NULL")
        let always = Date.distantPast ..< Date.distantFuture
        #expect(try await repositories.workouts.recent(limit: 5) == [])
        #expect(try await repositories.workouts.workouts(in: always) == [])
        #expect(try await repositories.stats.personalRecords(exerciseID: Self.bench.id) == [])
        #expect(try await repositories.stats.sessionsCompleted(in: always) == 0)
        #expect(try await repositories.stats.weeklyVolume(in: always) == .zero)
        #expect(try await repositories.stats.lastPerformance(exerciseID: Self.bench.id) == nil)
        #expect(try await repositories.stats.recentlyLogged(limit: 5) == [])
    }
}
