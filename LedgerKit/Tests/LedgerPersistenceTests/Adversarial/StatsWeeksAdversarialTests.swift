import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1, criterion 5 and the brief's risk "ISO week vs user weekStart": the weeks of
/// `e1RMByWeek` under every week start, across clock changes, a skipped day and the year's end, and at the
/// edges of `lastWeeks`. `HistoryModel` finds a workout's week by walking `WeekCalendar`'s ranges of instants
/// back from `now`; the query counts civil days. They must agree.
@Suite("Adversarial S3 · stats weeks", .tags(.persistence), .timeLimit(.minutes(1)))
struct StatsWeeksAdversarialTests {
    /// Bench workout `number` ending at `date`: one set whose estimate grows with `number`.
    static func session(_ number: Int, at date: Date, minutes: Double = 45) -> WorkoutState {
        S3Kit.workout(number, endedAt: date, minutes: minutes, [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(Decimal(100 + number), 5)])
        ])
    }

    static func estimate(_ number: Int) -> Weight {
        OneRepMax.brzycki(weight: .pounds(Decimal(100 + number)), reps: Reps(clamping: 5)) ?? .zero
    }

    /// Stores `workouts` in a database and in a model, and expects `e1RMByWeek` to agree for each `lastWeeks`.
    /// Returns the database's answers.
    static func agree(
        _ workouts: [WorkoutState],
        now: Date,
        _ calendar: WeekCalendar,
        lastWeeks: [Int]
    ) async throws -> [[WeekKey: Weight]] {
        let stack = try await S3Kit.stack()
        let model = HistoryModel(now: now)
        for workout in workouts {
            try await stack.materialize(workout)
            try await model.materialize(
                workout,
                summary: WorkoutEngine.summary(workout, prs: []),
                prs: [],
                slotUpdates: []
            )
        }
        var answers: [[WeekKey: Weight]] = []
        for weeks in lastWeeks {
            let stored = try await stack.stats(now: now).e1RMByWeek(
                exerciseID: S3Kit.bench,
                lastWeeks: weeks,
                calendar: calendar
            )
            let expected = try await model.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: weeks, calendar: calendar)
            #expect(stored == expected, "lastWeeks \(weeks)")
            answers.append(stored)
        }
        return answers
    }

    @Test(
        "A workout a day at noon for 24 days: each week start and time zone groups them as its own weeks",
        arguments: [
            "UTC", "America/New_York", "Pacific/Auckland", "Asia/Kathmandu", "Pacific/Kiritimati", "Pacific/Pago_Pago"
        ],
        Weekday.allCases
    )
    func everyWeekStart_groupsByItsOwnWeeks(zone: String, weekStart: Weekday) async throws {
        let calendar = S3Kit.calendar(zone, weekStart: weekStart)
        let workouts = (0 ..< 24).map { Self.session($0, at: S3Kit.instant(zone, 2026, 9, 1 + $0)) }
        let now = S3Kit.instant(zone, 2026, 9, 16, 5, 20)
        let answers = try await Self.agree(workouts, now: now, calendar, lastWeeks: [1, 2, 3, 100])
        // Stated directly for one week: the days from the week's start to its end, the last of them the best.
        let week = calendar.week(containing: now)
        let inWeek = workouts.indices.filter { week.contains(workouts[$0].endedAt ?? now) }
        #expect(inWeek.count == 7)
        #expect(answers[0] == [calendar.isoWeekKey(for: now): Self.estimate(inWeek.max() ?? 0)])
        #expect(answers[1].count == 2 && answers[3].count >= 3)
    }

    @Test("Clock changes and a skipped day move no workout into another week", arguments: [
        ["America/New_York", "2026-11-01"], ["America/New_York", "2026-03-08"], ["Africa/Cairo", "2026-04-24"],
        ["America/Santiago", "2026-09-06"], ["Pacific/Apia", "2011-12-31"], ["Australia/Lord_Howe", "2026-10-04"]
    ])
    func clockChanges_keepTheWeek(zoneAndDay: [String]) async throws {
        let zone = zoneAndDay[0]
        let day = try #require(CivilDate(iso8601: zoneAndDay[1]))
        let calendar = S3Kit.calendar(zone, weekStart: day.weekday) // the week starts on the day the clocks change
        let start = day.startOfDay(in: S3Kit.gregorian(zone))
        // Either side of the week's first instant, through the changed day, and a week either way.
        let offsets: [Double] = [
            -7 * 86400,
            -3600,
            -1,
            -0.001,
            0,
            0.001,
            1800,
            3600,
            5400,
            7200,
            90000,
            6 * 86400,
            8 * 86400
        ]
        let workouts = offsets.enumerated().map { Self.session($0, at: start.addingTimeInterval($1)) }
        let now = start.addingTimeInterval(3 * 86400)
        let answers = try await Self.agree(workouts, now: now, calendar, lastWeeks: [1, 2, 8])
        #expect(calendar.week(containing: now).lowerBound == start)
        #expect(answers[0] == [calendar.isoWeekKey(for: now): Self.estimate(11)], "the week holds offsets 0 to 6 days")
        #expect(
            answers[1].values.sorted() == [Self.estimate(3), Self.estimate(11)],
            "and the one before ends 1 ms earlier"
        )
    }

    @Test("The last week of 2026 is ISO week 53, and its key's year is 2026 on 2 January 2027")
    func yearBoundary_keysTheWeekYear() async throws {
        let dates = [(2026, 12, 27), (2026, 12, 28), (2027, 1, 1), (2027, 1, 3), (2027, 1, 4)]
        let workouts = dates.enumerated().map { Self.session($0, at: S3Kit.instant("UTC", $1.0, $1.1, $1.2)) }
        let now = S3Kit.instant("UTC", 2027, 1, 2, 9)
        let monday = try await Self.agree(workouts, now: now, S3Kit.calendar(), lastWeeks: [2, 60])
        let expected = [
            WeekKey(year: 2026, week: 53): Self.estimate(3),
            WeekKey(year: 2026, week: 52): Self.estimate(0)
        ]
        #expect(monday[0] == expected)
        #expect(monday[1] == expected, "the Monday after, 4 January 2027, is next week: no key")
        // From a Sunday the same days are two other weeks: 27 December to 2 January, then one not yet begun.
        let sunday = try await Self.agree(workouts, now: now, S3Kit.calendar(weekStart: .sunday), lastWeeks: [1])
        #expect(sunday[0].values.sorted() == [Self.estimate(2)])
    }

    /// (documents) Notes, question 7: a workout's date is when it ended.
    @Test("(documents) A workout begun on Sunday night that ends after midnight counts for Monday's week, whole")
    func midnightCrossing_countsForTheWeekItEndedIn() async throws {
        let stack = try await S3Kit.stack()
        let calendar = S3Kit.calendar()
        let monday = S3Kit.instant("UTC", 2026, 9, 14, 0, 10)
        var workout = Self.session(1, at: monday, minutes: 100)
        workout.exercises[0].sets[0].doneAt = monday.addingTimeInterval(-3600) // ticked on Sunday
        try await stack.materialize(workout)
        let stats = stack.stats()
        let thisWeek = calendar.week(containing: S3Kit.now)
        let lastWeek = calendar.previousCompleteWeek(before: S3Kit.now)
        #expect(try await stats.weeklyVolume(in: thisWeek) == workout.volume)
        #expect(try await stats.weeklyVolume(in: lastWeek) == .zero)
        #expect(try await stats.sessionsCompleted(in: lastWeek) == 0)
        #expect(try await stack.workouts.workouts(in: lastWeek) == [])
        let weeks = try await stats.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: 1, calendar: calendar)
        #expect(weeks == [WeekKey(year: 2026, week: 38): Self.estimate(1)])
    }

    @Test("lastWeeks below 1 gives none; 1 the current week, later days included; .max every past week, no later one")
    func lastWeeks_atItsEdges() async throws {
        let offsets: [Double] = [-800, -15, -8, -2, 0, 3, 5, 400]
        let workouts = offsets.enumerated().map { Self.session($0, at: S3Kit.day($1)) }
        let calendar = S3Kit.calendar()
        let answers = try await Self.agree(workouts, now: S3Kit.now, calendar, lastWeeks: [.min, -1, 0, 1, 2, 3, .max])
        #expect(answers[0] == [:] && answers[1] == [:] && answers[2] == [:])
        #expect(
            answers[3] == [WeekKey(year: 2026, week: 38): Self.estimate(5)],
            "Saturday of this week counts; Monday next does not"
        )
        #expect(answers[4].count == 2 && answers[5].count == 3)
        #expect(answers[6].count == 4, "800 days back counts; 400 days ahead and next Monday never do")
        // A current time long after, or before, every workout.
        let later = try await Self.agree(workouts, now: S3Kit.day(5000), calendar, lastWeeks: [8])
        let earlier = try await Self.agree(workouts, now: S3Kit.day(-5000), calendar, lastWeeks: [8, .max])
        #expect(later == [[:]] && earlier == [[:], [:]])
    }
}
