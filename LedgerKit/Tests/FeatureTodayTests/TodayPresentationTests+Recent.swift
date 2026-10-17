@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The RECENT list (specification criterion 9; the body's criterion 10).
nonisolated extension TodayPresentationTests {
    /// Seven finished workouts, newest first: one today and one on each of the six days before.
    static func sevenWorkouts() throws -> [WorkoutState] {
        try [
            TodayFixtures.workout(
                7,
                named: "Lower A — Squat focus",
                pounds: 8120,
                startedAt: Fixtures.date(2026, 9, 16, hour: 4),
                seconds: 1462
            ),
            TodayFixtures.workout(6, named: "Upper A — Push focus", pounds: 17020, startedAt: day(15), seconds: 2940),
            TodayFixtures.workout(5, named: "Lower A — Squat focus", pounds: 24180, startedAt: day(14)),
            TodayFixtures.workout(4, named: "Upper B — Pull focus", pounds: 17020, startedAt: day(13), seconds: 2999),
            TodayFixtures.workout(3, named: "Lower B — Hinge focus", pounds: 26400, startedAt: day(12), seconds: 3660),
            TodayFixtures.workout(2, pounds: 100, startedAt: day(11)),
            TodayFixtures.workout(1, pounds: 100, startedAt: day(10))
        ]
    }

    /// 07:00 on that day of September 2026.
    static func day(_ day: Int) -> Date {
        Fixtures.date(2026, 9, day, hour: 7)
    }

    @Test("Of seven finished workouts the five newest are listed, newest first, each opening itself (criterion 10)")
    func recent_fiveNewestFirst_todayLabel() throws {
        var input = try TodayFixtures.input()
        input.recentWorkouts = try Self.sevenWorkouts()
        let recent = TodayPresentation.make(input).recent
        #expect(recent.eyebrow == "RECENT")
        #expect(recent.emptyMessage == nil)
        #expect(recent.rows.map(\.name) == [
            "Lower A — Squat focus", "Upper A — Push focus", "Lower A — Squat focus", "Upper B — Pull focus",
            "Lower B — Hinge focus"
        ])
        #expect(recent.rows.map(\.meta) == [
            "Today · 24:22 · 8,120 lb", "Tue · 49 min · 17,020 lb", "Mon · 58 min · 24,180 lb",
            "Sun · 49 min · 17,020 lb", "Sat · 61 min · 26,400 lb"
        ])
        #expect(recent.rows.map(\.route) == (3 ... 7).reversed().map { .openWorkout(WorkoutID(Fixtures.uuid($0))) })
    }

    @Test("With no finished workout the list is empty and says so")
    func recent_none_showsTheEmptyCopy() throws {
        let recent = try TodayPresentation.make(TodayFixtures.input()).recent
        #expect(recent.rows.isEmpty)
        #expect(recent.emptyMessage == "No sessions yet. Your first workout lands here.")
        #expect(recent.eyebrow == "RECENT")
    }

    @Test("A workout's length is its whole minutes, rounded down as the clock text rounds seconds")
    func recent_minutes_areRoundedDown() throws {
        var input = try TodayFixtures.input()
        input.recentWorkouts = try [
            TodayFixtures.workout(3, pounds: 100, startedAt: Self.day(15), seconds: 3599),
            TodayFixtures.workout(2, pounds: 100, startedAt: Self.day(14), seconds: 60),
            TodayFixtures.workout(1, pounds: 100, startedAt: Self.day(13), seconds: 59)
        ]
        let meta = TodayPresentation.make(input).recent.rows.map(\.meta)
        #expect(meta == ["Tue · 59 min · 100 lb", "Mon · 1 min · 100 lb", "Sun · 0 min · 100 lb"])
    }

    @Test("In kilograms the volumes convert and read kg")
    func recent_kilograms_convert() throws {
        var input = try TodayFixtures.input(program: TodayFixtures.program(), settings: Fixtures.settingsKg)
        input.recentWorkouts = try Array(Self.sevenWorkouts().prefix(3))
        let meta = TodayPresentation.make(input).recent.rows.map(\.meta)
        #expect(meta == ["Today · 24:22 · 3,683 kg", "Tue · 49 min · 7,720 kg", "Mon · 58 min · 10,968 kg"])
    }

    @Test("Today is the calendar day in the injected zone: a workout from earlier today elsewhere is yesterday's")
    func recent_todayLabel_followsTheZone() throws {
        var input = try TodayFixtures.input()
        // 04:00 UTC on Wednesday the 16th is 21:00 on Tuesday in Los Angeles; so is `now`, 05:20 UTC.
        input.recentWorkouts = try [TodayFixtures.workout(
            1,
            pounds: 100,
            startedAt: Fixtures.date(2026, 9, 16, hour: 4)
        )]
        #expect(TodayPresentation.make(input).recent.rows.first?.meta == "Today · 58:00 · 100 lb")
        input.calendar = try TodayFixtures.calendar(in: "America/Los_Angeles")
        #expect(TodayPresentation.make(input).recent.rows.first?.meta == "Today · 58:00 · 100 lb")
        // At 07:30 UTC it is Wednesday in Los Angeles, and the workout is Tuesday's.
        input.now = Fixtures.date(2026, 9, 16, hour: 7, minute: 30)
        #expect(TodayPresentation.make(input).recent.rows.first?.meta == "Tue · 58 min · 100 lb")
    }

    @Test("A workout older than a week reads its weekday all the same")
    func recent_olderThanAWeek_readsItsWeekday() throws {
        var input = try TodayFixtures.input()
        input.recentWorkouts = try [TodayFixtures.workout(
            1,
            pounds: 100,
            startedAt: Fixtures.date(2026, 8, 19, hour: 7)
        )]
        #expect(TodayPresentation.make(input).recent.rows.first?.meta == "Wed · 58 min · 100 lb")
    }

    @Test("The session's workout, just finished, heads the list by its start, and is listed once")
    func recent_finishedSession_joinsTheListByItsStart() throws {
        var input = try TodayFixtures.input()
        let stored = try Array(Self.sevenWorkouts().dropFirst())
        input.recentWorkouts = stored
        // Finished a moment ago, started after everything stored.
        input.session = try TodayFixtures.workout(40, pounds: 5000, startedAt: Fixtures.date(2026, 9, 16, hour: 4))
        let heads = TodayPresentation.make(input).recent.rows
        #expect(heads.count == 5)
        #expect(heads.first?.route == .openWorkout(WorkoutID(Fixtures.uuid(40))))
        #expect(heads.last?.route == .openWorkout(WorkoutID(Fixtures.uuid(3))))
        // One that started before some stored workouts takes its place among them.
        input.session = try TodayFixtures.workout(41, pounds: 5000, startedAt: Fixtures.date(2026, 9, 14, hour: 12))
        let ids = TodayPresentation.make(input).recent.rows.map(\.route)
        #expect(ids == [6, 41, 5, 4, 3].map { .openWorkout(WorkoutID(Fixtures.uuid($0))) })
        // Older than all of them, it goes last, beyond the five.
        input.session = try TodayFixtures.workout(42, pounds: 5000, startedAt: Fixtures.date(2026, 9, 1, hour: 12))
        let last = TodayPresentation.make(input).recent.rows.map(\.route)
        #expect(last == [6, 5, 4, 3, 2].map { .openWorkout(WorkoutID(Fixtures.uuid($0))) })
        input.recentWorkouts = []
        #expect(TodayPresentation.make(input).recent.rows.map(\.route) == [.openWorkout(WorkoutID(Fixtures.uuid(42)))])
    }
}
