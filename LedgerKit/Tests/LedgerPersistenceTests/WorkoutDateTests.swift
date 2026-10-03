import Foundation
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Product decision #26: a workout belongs to the day, and the week, in which it started. A session begun at
/// 23:30 and finished at 00:40 is the earlier day's in every list and stats query, whatever the calendar's week
/// start, and however its sets were ticked.
@Suite("A workout's day is its start", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutDateTests {
    static let bench = WorkoutRepositoryContract.exercises[0]

    /// 23:30 UTC on `day` of September 2026.
    static func lateStart(_ day: Int) throws -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 23, minute: 30)))
    }

    /// A 70-minute bench workout from `start`, its one set ticked after midnight.
    static func late(_ number: Int, startingAt start: Date) -> WorkoutState {
        Seeders.workout(
            number: number,
            endedAt: WorkoutRepositoryContract.ending(startedAt: start, minutes: 70),
            minutes: 70,
            [.straight(bench, sets: 1, reps: 5, pounds: 200)]
        )
    }

    @Test("Tuesday 23:30 to Wednesday 00:40 is Tuesday's: its day range, the Last line's date, and the list order")
    func lateWorkout_isTheDayItStarted() async throws {
        let repositories = try Repositories()
        let tuesday = try Self.lateStart(15)
        let late = Self.late(1, startingAt: tuesday)
        // Started after the late one (Wednesday 00:10) and ended before it: it lists first.
        let early = Seeders.workout(
            number: 2,
            endedAt: tuesday.addingTimeInterval(4000),
            minutes: 10,
            [.straight(WorkoutRepositoryContract.exercises[1], sets: 1, reps: 5, pounds: 100)]
        )
        try await repositories.history.materialize(late)
        try await repositories.history.materialize(early)
        let tuesdayRange = tuesday.addingTimeInterval(-23.5 * 3600) ..< tuesday.addingTimeInterval(0.5 * 3600)
        let wednesdayRange = tuesdayRange.upperBound ..< tuesdayRange.upperBound.addingTimeInterval(86400)
        #expect(try await repositories.workouts.workouts(in: tuesdayRange) == [late])
        #expect(try await repositories.workouts.workouts(in: wednesdayRange) == [early])
        #expect(try await repositories.workouts.recent(limit: 2) == [early, late])
        #expect(try await repositories.stats.sessionsCompleted(in: tuesdayRange) == 1)
        #expect(try await repositories.stats.weeklyVolume(in: tuesdayRange) == late.volume)
        #expect(try await repositories.stats.lastPerformance(exerciseID: Self.bench.id)?.date == tuesday)
        #expect(try await repositories.stats.recentlyLogged(limit: 2) == [
            WorkoutRepositoryContract.exercises[1].id, Self.bench.id
        ])
    }

    @Test(
        "Sunday 23:30 to Monday 00:40 is last week's with weeks from Monday; Saturday night with weeks from Sunday",
        arguments: [Weekday.monday, .sunday]
    )
    func lateWorkout_isTheWeekItStarted(weekStart: Weekday) async throws {
        let repositories = try Repositories()
        let calendar = try StatsQueriesContract.calendar(weekStart: weekStart)
        // The night before the week that holds `now` (Wednesday 16 September) begins: Sunday 13th or Saturday 12th.
        let start = try Self.lateStart(weekStart == .monday ? 13 : 12)
        let late = Self.late(1, startingAt: start)
        try await repositories.history.materialize(late)
        let now = StatsQueriesContract.now
        let thisWeek = calendar.week(containing: now)
        let lastWeek = calendar.previousCompleteWeek(before: now)
        #expect(late.endedAt.map(thisWeek.contains) == true, "it ends in this week")
        let stats = repositories.stats
        #expect(try await repositories.workouts.workouts(in: lastWeek) == [late])
        #expect(try await repositories.workouts.workouts(in: thisWeek) == [])
        #expect(try await stats.sessionsCompleted(in: lastWeek) == 1)
        #expect(try await stats.sessionsCompleted(in: thisWeek) == 0)
        #expect(try await stats.weeklyVolume(in: lastWeek) == late.volume)
        #expect(try await stats.weeklyVolume(in: thisWeek) == .zero)
        let estimate = try #require(OneRepMax.brzycki(weight: .pounds(200), reps: Reps(clamping: 5)))
        #expect(try await stats.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: 1, calendar: calendar) == [:])
        #expect(try await stats.e1RMByWeek(exerciseID: Self.bench.id, lastWeeks: 2, calendar: calendar) == [
            calendar.isoWeekKey(for: start): estimate
        ])
    }
}
