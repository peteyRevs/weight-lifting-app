import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3, product decision #26 (Pete, 2026-10-02): a workout belongs to the day and the week it **started**.
/// Workouts whose start and end fall in different days, weeks, months or years; equal starts; a start after
/// the end; the rows with no end; and the v002 index on old and new files.
@Suite("Adversarial S3 · decision #26, dating by the start", .tags(.persistence), .timeLimit(.minutes(1)))
struct WorkoutStartDateAdversarialTests {
    /// Bench workout `number` from `start` for `minutes`, one set ticked at the end.
    static func session(_ number: Int, from start: Date, minutes: Double, pounds: Decimal = 200) -> WorkoutState {
        S3Kit.workout(number, endedAt: start.addingTimeInterval(60 * minutes), minutes: minutes, [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(pounds, 5)])
        ])
    }

    /// Every list and stats answer for `range`, as one value to compare.
    static func answers(_ stack: S3Kit.Stack, _ range: Range<Date>, now: Date) async throws -> [String] {
        let stats = stack.stats(now: now)
        return try await [
            "\(stack.workouts.workouts(in: range).map(\.id))",
            "\(stats.weeklyVolume(in: range))",
            "\(stats.sessionsCompleted(in: range))"
        ]
    }

    @Test("A workout from New Year's Eve to New Year's Day is 2026's: its day, week (W53), month and year", arguments: [
        "UTC", "Pacific/Kiritimati", "America/Los_Angeles"
    ])
    func acrossTheYear_isTheStartsDayWeekMonthAndYear(zone: String) async throws {
        let stack = try await S3Kit.stack()
        let start = S3Kit.instant(zone, 2026, 12, 31, 23, 30)
        let workout = Self.session(1, from: start, minutes: 70)
        try await stack.materialize(workout)
        let calendar = S3Kit.calendar(zone)
        let gregorian = S3Kit.gregorian(zone)
        let day = gregorian.dateInterval(of: .day, for: start)
        let month = gregorian.dateInterval(of: .month, for: start)
        let year = gregorian.dateInterval(of: .year, for: start)
        let nextYear = gregorian.dateInterval(of: .year, for: start.addingTimeInterval(86400))
        let now = S3Kit.instant(zone, 2027, 1, 2, 9)
        for (name, interval) in [("day", day), ("month", month), ("year", year)] {
            let range = try #require(interval).start ..< (try #require(interval)).end
            #expect(
                try await Self.answers(stack, range, now: now) == ["\([workout.id])", "\(workout.volume)", "1"],
                "\(name)"
            )
        }
        let next = try #require(nextYear)
        #expect(try await Self.answers(stack, next.start ..< next.end, now: now) == ["[]", "\(Volume.zero)", "0"])
        let weeks = try await stack.stats(now: now).e1RMByWeek(
            exerciseID: S3Kit.bench,
            lastWeeks: 1,
            calendar: calendar
        )
        #expect(weeks == [WeekKey(year: 2026, week: 53): Self.estimate(200)])
        #expect(try await stack.stats().lastPerformance(exerciseID: S3Kit.bench)?.date == start)
    }

    static func estimate(_ pounds: Decimal) -> Weight {
        OneRepMax.brzycki(weight: .pounds(pounds), reps: Reps(clamping: 5)) ?? .zero
    }

    @Test(
        "Workouts started together list by id whatever their ends; a later start lists first though it ended first"
    )
    func equalStarts_tieByID_notByEnd() async throws {
        let stack = try await S3Kit.stack()
        let start = S3Kit.day(-1)
        let short = Self.session(2, from: start, minutes: 10, pounds: 300)
        let long = Self.session(1, from: start, minutes: 300, pounds: 100)
        let later = Self.session(3, from: start.addingTimeInterval(60), minutes: 1, pounds: 150)
        for workout in [short, later, long] {
            try await stack.materialize(workout)
        }
        #expect(try await stack.workouts.recent(limit: 3) == [later, long, short])
        #expect(try await stack.workouts.recent(limit: 2) == [later, long])
        #expect(try await stack.workouts.workouts(in: start ..< start.addingTimeInterval(1)) == [long, short])
        try await stack.workouts.delete(id: later.id)
        let line = try await stack.stats().lastPerformance(exerciseID: S3Kit.bench)
        #expect(
            line == LastPerformance(date: start, sets: 1, reps: 5, load: .pounds(100)),
            "the smaller id, not the later end"
        )
        #expect(try await stack.stats().recentlyLogged(limit: 1) == [S3Kit.bench])
    }

    /// (documents) Nothing refuses a workout that ends before it starts (the engine's clock rules are F04's), and
    /// every query then reads its start alone: the end decides nothing but that the row has one.
    @Test("(documents) A workout that ends before it starts is stored, and dated by its start everywhere")
    func endBeforeStart_isDatedByItsStart() async throws {
        let stack = try await S3Kit.stack()
        let calendar = S3Kit.calendar()
        let start = calendar.week(containing: S3Kit.now).lowerBound
        var backwards = Self.session(1, from: start, minutes: 45)
        backwards.endedAt = start.addingTimeInterval(-86400 * 8) // two weeks back
        try await stack.materialize(backwards)
        let thisWeek = calendar.week(containing: S3Kit.now)
        let lastWeek = calendar.previousCompleteWeek(before: S3Kit.now)
        #expect(try await Self.answers(stack, thisWeek, now: S3Kit.now) == [
            "\([backwards.id])",
            "\(backwards.volume)",
            "1"
        ])
        #expect(try await Self.answers(stack, lastWeek, now: S3Kit.now) == ["[]", "\(Volume.zero)", "0"])
        let weeks = try await stack.stats().e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: 1, calendar: calendar)
        #expect(weeks == [calendar.isoWeekKey(for: S3Kit.now): Self.estimate(200)])
        #expect(try await stack.workouts.recent(limit: 1) == [backwards])
        #expect(backwards.elapsed(at: S3Kit.now) == .zero)
    }

    @Test(
        "A finished row with its end cleared is in no list, range or stat; it reads by id, and a rebuild repairs it"
    )
    func noEnd_countsNowhere_butReadsByID() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1)
        let other = S3Kit.mixed(2, endedAt: S3Kit.day(-1))
        let record = S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(215)), in: workout)
        try await stack.materialize(workout, prs: [record])
        try await stack.materialize(other)
        try await stack.execute("UPDATE workout SET ended_at = NULL WHERE id = ?", [workout.id.rawValue.uuidString])
        let always = Date.distantPast ..< Date.distantFuture
        let stats = stack.stats()
        #expect(try await stack.workouts.recent(limit: 1) == [other], "the row took a place of the limit")
        #expect(try await stack.workouts.workouts(in: always) == [other])
        #expect(try await stats.sessionsCompleted(in: always) == 1)
        #expect(try await stats.weeklyVolume(in: always) == other.volume)
        #expect(try await stats.personalRecords(exerciseID: S3Kit.bench) == [])
        #expect(try await stats.bestSet(exerciseID: S3Kit.bench)?.weight == .pounds(190))
        let model = HistoryModel(now: S3Kit.now)
        try await model.materialize(other, summary: WorkoutEngine.summary(other, prs: []), prs: [], slotUpdates: [])
        let calendar = S3Kit.calendar()
        #expect(try await stats.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: .max, calendar: calendar)
            == model.e1RMByWeek(exerciseID: S3Kit.bench, lastWeeks: .max, calendar: calendar))
        #expect(try await stats.lastPerformance(exerciseID: S3Kit.bench)?.date == other.startedAt)
        // By id it reads as stored, with no end; a rebuild repairs it.
        #expect(try await stack.workouts.workout(id: workout.id)?.endedAt == nil)
        try await stack.materialize(workout, prs: [record])
        #expect(try await stack.workouts.recent(limit: 1) == [workout])
    }
}

extension WorkoutStartDateAdversarialTests {
    @Test("v002 on the v001 fixture and on a used file: once, then a no-op; a failed later migration keeps it")
    func v002_onOldFiles() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let fixture = try MigrationFixtureAdversarialTests.copy(in: directory)
        var failing = LedgerDatabase.migrator
        failing.registerMigration("v999_fails") { _ in throw CancellationError() }
        #expect(throws: CancellationError.self) { try failing.migrate(fixture) }
        #expect(try await fixture.read(LedgerDatabase.migrator.appliedIdentifiers) == [
            "v001_createSchema", "v002_workoutStartedIndex"
        ])
        let before = try await fixture.read { try MigrationFixtureAdversarialTests.rows($0) }
        try fixture.close()
        for _ in 0 ..< 2 {
            let opened = try LedgerDatabase.open(at: directory.file("fixture.sqlite"))
            #expect(try await opened.read { try MigrationFixtureAdversarialTests.rows($0) } == before)
            let indexes = try await opened.read { database in
                try String.fetchAll(database, sql: "SELECT sql FROM sqlite_master WHERE name = 'idx_workout_started'")
            }
            #expect(indexes == ["CREATE INDEX idx_workout_started ON workout(started_at DESC, id)"])
            let history = try await GRDBWorkoutRepository(opened).recent(limit: 10)
            #expect(history.map(\.startedAt) == history.map(\.startedAt).sorted(by: >))
            #expect(history.count == 2)
            try opened.close()
        }
    }

    /// (documents) Finding S3-N5. v002 is a plain `CREATE INDEX`, as v001's statements are: a file that
    /// already holds an index of that name (a foreign tool, or a build that shipped one) cannot be opened.
    @Test("(documents) A file that already has an index named idx_workout_started fails to open")
    func preexistingIndexName_failsTheMigration() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let fixture = try MigrationFixtureAdversarialTests.copy(in: directory)
        try await fixture.write { database in
            try database.execute(sql: "CREATE INDEX idx_workout_started ON workout(started_at)")
        }
        try fixture.close()
        #expect(throws: DatabaseError.self) { _ = try LedgerDatabase.open(at: directory.file("fixture.sqlite")) }
    }
}
