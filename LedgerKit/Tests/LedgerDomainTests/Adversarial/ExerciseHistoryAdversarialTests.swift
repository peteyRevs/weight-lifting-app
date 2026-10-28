import Foundation
@testable import LedgerDomain
import Testing

/// F12 S2 adversarial round 1 (G2): `ExerciseHistory.make` where its own tests are silent. Brzycki at its edges
/// (one rep, twelve and thirteen, forty, no load); the tags against `PersonalRecords` over random histories (one
/// workout's records judged against the bests before it, as F05 stores them); the eight weeks across a year's end,
/// both changes of clocks, a midnight a time zone skips, a calendar whose own first weekday differs, and the
/// window's two edges; a workout that does the exercise on two rows; pounds beside kilograms.
@Suite("Adversarial F12 S2 · ExerciseHistory", .tags(.domain))
struct ExerciseHistoryAdversarialTests {
    typealias Spec = ExerciseHistoryTests.Spec

    static func session(_ number: Int, on date: Date, _ sets: [Spec]) -> ExerciseSession {
        ExerciseHistoryTests.session(number, on: date, sets)
    }

    static func session(_ number: Int, on date: Date, weights: [Weight], kind: SetKind = .working) -> ExerciseSession {
        ExerciseSession(
            workoutID: WorkoutID(Fixtures.uuid(4000 + number)),
            startedAt: date,
            sets: weights.enumerated().map { place, weight in
                LoggedSet(
                    id: SetID(Fixtures.uuid(30000 + number * 20 + place)),
                    weight: weight,
                    reps: Reps(clamping: 5),
                    kind: kind,
                    doneAt: date
                )
            }
        )
    }

    static func weeks(_ weekStart: Weekday, _ calendar: Calendar = Fixtures.calendar) -> WeekCalendar {
        WeekCalendar(startDate: .unixEpoch, weekStart: weekStart, calendar: calendar)
    }

    static func make(_ sessions: [ExerciseSession], now: Date, calendar: WeekCalendar) -> ExerciseHistory {
        ExerciseHistory.make(sessions: sessions, records: [], now: now, calendar: calendar)
    }

    /// The eight weeks follow each other with no gap and no overlap, and the last holds `now`.
    static func isContiguous(_ history: ExerciseHistory, now: Date, calendar: WeekCalendar) -> Bool {
        let current = calendar.week(containing: now)
        let ranges = history.weeks.map { calendar.week(containing: $0.start) }
        return ranges.count == ExerciseHistory.chartWeeks && ranges.last == current
            && zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound }
            && zip(ranges, history.weeks).allSatisfy { $0.lowerBound == $1.start }
    }

    // MARK: Brzycki at its edges

    @Test("One rep: the estimate is the weight itself, to the gram")
    func e1RM_oneRep_isTheWeight() {
        let history = Self.make(
            [Self.session(1, on: Fixtures.now, [(185, 1, .working)])],
            now: Fixtures.now,
            calendar: Self.weeks(.monday)
        )
        #expect(history.e1RM == Weight(grams: Weight.pounds(185).grams.rounded(scale: 0, .toNearestOrAwayFromZero)))
        #expect(history.weeks.last?.e1RM == history.e1RM)
    }

    @Test("Twelve reps count and thirteen do not: a lighter 12-rep set gives the estimate over a heavier 13")
    func e1RM_twelveAndThirteenReps_onlyTwelveCounts() {
        let history = Self.make(
            [Self.session(1, on: Fixtures.now, [(100, 12, .working), (300, 13, .working)])],
            now: Fixtures.now,
            calendar: Self.weeks(.monday)
        )
        #expect(history.e1RM == OneRepMax.brzycki(weight: .pounds(100), reps: Reps(clamping: 12)))
        #expect(history.bestSet == BestSet(weight: .pounds(300), reps: Reps(clamping: 13)))
    }

    @Test("Forty reps, past Brzycki's 37: no estimate and no trap, and the set is still the best set")
    func e1RM_fortyReps_hasNoEstimateAndStaysTheBestSet() {
        let history = Self.make(
            [Self.session(1, on: Fixtures.now, [(135, 40, .working), (135, 37, .added)])],
            now: Fixtures.now,
            calendar: Self.weeks(.monday)
        )
        #expect(history.e1RM == nil)
        #expect(history.weeks.allSatisfy { $0.e1RM == nil })
        #expect(history.bestSet == BestSet(weight: .pounds(135), reps: Reps(clamping: 40)))
    }

    /// As F12-S1-3 (Pete approved "0" for a zero-load best on the Library, 2026-10-22): a bodyweight exercise done
    /// at no load has an estimate of zero, not none, so its history charts a zero.
    @Test("No load: the estimate is zero, not nil, and the week charts it")
    func e1RM_zeroLoad_isZeroNotNil() {
        let history = Self.make(
            [Self.session(1, on: Fixtures.now, [(0, 12, .working), (0, 15, .working)])],
            now: Fixtures.now,
            calendar: Self.weeks(.monday)
        )
        #expect(history.e1RM == .zero)
        #expect(history.weeks.last?.e1RM == .zero)
        #expect(history.bestSet == BestSet(weight: .zero, reps: Reps(clamping: 15)))
    }
}

extension ExerciseHistoryAdversarialTests {
    // MARK: Weeks

    @Test("Across a year's end: from Monday and from Sunday the weeks run on through New Year's Day", arguments: [
        Weekday.monday, .sunday, .saturday
    ])
    func weeks_acrossNewYear_runOnUnbroken(_ weekStart: Weekday) {
        // Wednesday 2027-01-06: W1 lies in November 2026.
        let now = Fixtures.date(2027, 1, 6, hour: 12)
        let calendar = Self.weeks(weekStart)
        let eve = Self.session(2, on: Fixtures.date(2026, 12, 31, hour: 20), [(200, 5, .working)])
        let newYear = Self.session(1, on: Fixtures.date(2027, 1, 1, hour: 9), [(210, 5, .working)])
        let history = Self.make([newYear, eve], now: now, calendar: calendar)
        #expect(Self.isContiguous(history, now: now, calendar: calendar))
        // Each week's expected best: the heavier of the two sessions that started in it.
        var expected: [Date: Weight] = [:]
        for (session, pounds) in [(eve, Decimal(200)), (newYear, 210)] {
            let start = calendar.week(containing: session.startedAt).lowerBound
            expected[start] = max(expected[start] ?? .zero, .pounds(pounds))
        }
        let found = history.weeks.map(\.e1RM)
        let wanted = history.weeks.map { week in
            expected[week.start].flatMap { OneRepMax.brzycki(weight: $0, reps: Reps(clamping: 5)) }
        }
        #expect(found == wanted, "\(weekStart)")
        #expect(found.count { $0 != nil } == expected.count, "\(weekStart): both sessions are in the window")
    }

    @Test("Spring forward: the 167-hour week holds its own last minute, and the next opens at its midnight")
    func weeks_springForward_boundariesAreMidnights() throws {
        var newYork = Fixtures.calendar
        newYork.timeZone = try Fixtures.zone("America/New_York")
        let zone = newYork.timeZone
        let calendar = Self.weeks(.monday, newYork)
        // 2027-03-14 is the spring-forward Sunday; its Monday week (Mar 8 – 14) has 167 hours.
        let lastMinute = Self.session(
            2,
            on: Fixtures.date(2027, 3, 14, hour: 23, minute: 59, in: zone),
            [(200, 5, .working)]
        )
        let midnight = Self.session(1, on: Fixtures.date(2027, 3, 15, in: zone), [(220, 5, .working)])
        let now = Fixtures.date(2027, 3, 17, hour: 12, in: zone)
        let history = Self.make([midnight, lastMinute], now: now, calendar: calendar)
        #expect(Self.isContiguous(history, now: now, calendar: calendar))
        #expect(history.weeks[6].start == Fixtures.date(2027, 3, 8, in: zone))
        #expect(history.weeks[7].start == Fixtures.date(2027, 3, 15, in: zone))
        #expect(history.weeks[6].e1RM == OneRepMax.brzycki(weight: .pounds(200), reps: Reps(clamping: 5)))
        #expect(history.weeks[7].e1RM == OneRepMax.brzycki(weight: .pounds(220), reps: Reps(clamping: 5)))
        let hours = history.weeks[7].start.timeIntervalSince(history.weeks[6].start) / 3600
        #expect(hours == 167)
    }

    @Test("A skipped midnight (Santiago, 2026-09-06): the Sunday week opens at 01:00 and holds a 01:30 session")
    func weeks_skippedMidnight_weekOpensAtOne() throws {
        var santiago = Fixtures.calendar
        santiago.timeZone = try Fixtures.zone("America/Santiago")
        let zone = santiago.timeZone
        let calendar = Self.weeks(.sunday, santiago)
        let opening = Self.session(
            1,
            on: Fixtures.date(2026, 9, 6, hour: 1, minute: 30, in: zone),
            [(200, 5, .working)]
        )
        let before = Self.session(
            2,
            on: Fixtures.date(2026, 9, 5, hour: 23, minute: 30, in: zone),
            [(180, 5, .working)]
        )
        let now = Fixtures.date(2026, 9, 9, hour: 12, in: zone)
        let history = Self.make([opening, before], now: now, calendar: calendar)
        #expect(Self.isContiguous(history, now: now, calendar: calendar))
        #expect(history.weeks[7].start == Fixtures.date(2026, 9, 6, hour: 1, in: zone))
        #expect(history.weeks[7].e1RM == OneRepMax.brzycki(weight: .pounds(200), reps: Reps(clamping: 5)))
        #expect(history.weeks[6].e1RM == OneRepMax.brzycki(weight: .pounds(180), reps: Reps(clamping: 5)))
    }

    @Test("The weeks start on Settings' day, never on the calendar's own first weekday", arguments: [1, 2, 4, 7])
    func weeks_calendarFirstWeekday_isIgnored(_ firstWeekday: Int) {
        var calendar = Fixtures.calendar
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        let history = ExerciseHistory.make(
            sessions: [], records: [], now: Fixtures.now, weekStart: .monday, calendar: calendar
        )
        // Wednesday 2026-09-16: the current Monday week opens on the 14th.
        #expect(history.weeks.last?.start == Fixtures.date(2026, 9, 14), "first weekday \(firstWeekday)")
        #expect(history.weeks.first?.start == Fixtures.date(2026, 7, 27))
    }

    @Test("The window's edges: W1's first instant is in, the instant before is out, and so is the week after now")
    func weeks_windowEdges_firstInstantInAndTheRestOut() {
        let calendar = Self.weeks(.monday)
        let first = Fixtures.date(2026, 7, 27)
        let end = Fixtures.date(2026, 9, 21)
        let sessions = [
            Self.session(4, on: end, [(400, 5, .working)]),
            Self.session(3, on: end.addingTimeInterval(-1), [(300, 5, .working)]),
            Self.session(2, on: first, [(150, 5, .working)]),
            Self.session(1, on: first.addingTimeInterval(-1), [(500, 5, .working)])
        ]
        let history = Self.make(sessions, now: Fixtures.now, calendar: calendar)
        let estimate = { (pounds: Decimal) in OneRepMax.brzycki(weight: .pounds(pounds), reps: Reps(clamping: 5)) }
        #expect(history.weeks.first?.e1RM == estimate(150), "the Sunday before W1 is not in it")
        #expect(history.weeks.last?.e1RM == estimate(300), "a later session this week is in W8; next week's is not")
        #expect(history.weeks.dropFirst().dropLast().allSatisfy { $0.e1RM == nil })
        #expect(history.sessions == 4 && history.log.count == 4, "every session is still counted and logged")
        #expect(history.e1RM == estimate(500), "the estimate is over all history, not the window")
    }

    @Test("Older history only: every week is empty, while the estimate, best and log are kept")
    func weeks_onlyOlderHistory_allEmptyStatsKept() {
        let old = Self.session(1, on: Fixtures.date(2026, 1, 5), [(225, 5, .working)])
        let history = Self.make([old], now: Fixtures.now, calendar: Self.weeks(.monday))
        #expect(history.weeks.allSatisfy { $0.e1RM == nil })
        #expect(history.e1RM != nil && history.bestSet != nil && history.log.count == 1)
    }
}

extension ExerciseHistoryAdversarialTests {
    // MARK: Tags

    @Test("Two rows of one workout are one session: its top working weight is the heavier row's")
    func tags_twoRowsOneWorkout_compareTheHeavierRow() {
        let before = Self.session(1, on: Fixtures.date(2026, 9, 1), [(200, 5, .working)])
        // Row one 195 × 5, row two 205 × 3: the session as `exerciseSessions` merges them, in row order.
        let twice = Self.session(2, on: Fixtures.date(2026, 9, 8), [(195, 5, .working), (205, 3, .working)])
        let history = Self.make([twice, before], now: Fixtures.now, calendar: Self.weeks(.monday))
        #expect(history.log.map(\.tag) == [.heavier(.pounds(5)), .same])
        #expect(history.log.first?.sets.count == 2)
    }

    @Test("Pounds beside kilograms: 100 lb after 45.359237 kg is the same weight, exactly")
    func tags_poundsAfterTheSameKilograms_isSame() throws {
        // From text: a float literal would pass through `Double` and miss the exact value.
        let exact = try #require(Decimal(string: "45.359237"))
        let kilograms = Self.session(1, on: Fixtures.date(2026, 9, 1), weights: [.kilograms(exact)])
        let pounds = Self.session(2, on: Fixtures.date(2026, 9, 8), weights: [.pounds(100)])
        let history = Self.make([pounds, kilograms], now: Fixtures.now, calendar: Self.weeks(.monday))
        #expect(Weight.pounds(100) == .kilograms(exact))
        #expect(history.log.map(\.tag) == [.same, .same])
    }

    @Test("Pounds beside kilograms: the step up is exact, 100 lb less 45 kg")
    func tags_poundsAfterLighterKilograms_stepIsExact() {
        let kilograms = Self.session(1, on: Fixtures.date(2026, 9, 1), weights: [.kilograms(45)])
        let pounds = Self.session(2, on: Fixtures.date(2026, 9, 8), weights: [.pounds(100)])
        let history = Self.make([pounds, kilograms], now: Fixtures.now, calendar: Self.weeks(.monday))
        #expect(history.log.first?.tag == .heavier(Weight(grams: Weight.pounds(100).grams - 45000)))
    }

    /// F12-S2-5, changed by N19 (S3 amendments): "+Δ" compares with the latest earlier session that has a set
    /// counting toward bests, so a predecessor of warm-ups and drop sets alone no longer hides a step up. (As built
    /// in S2 this was pinned as "—"; the orchestrator's S3 amendment changed the rule, and this pin with it.)
    @Test("A predecessor with no set that counts is passed over: the step is from the session before it")
    func tags_predecessorWithoutCountedSets_isPassedOver() {
        let first = Self.session(1, on: Fixtures.date(2026, 9, 1), [(200, 5, .working)])
        let warmupsOnly = Self.session(2, on: Fixtures.date(2026, 9, 5), [(210, 3, .warmup), (180, 8, .drop)])
        let third = Self.session(3, on: Fixtures.date(2026, 9, 8), [(210, 5, .working)])
        let history = Self.make([third, warmupsOnly, first], now: Fixtures.now, calendar: Self.weeks(.monday))
        #expect(history.log.map(\.tag) == [.heavier(.pounds(10)), .same, .same])
    }

    @Test("Of two sessions that started together, the later in the list is the one before")
    func tags_sameStart_listOrderDecides() {
        let start = Fixtures.date(2026, 9, 8, hour: 7)
        let lighter = Self.session(2, on: start, [(200, 5, .working)])
        let heavier = Self.session(1, on: start, [(210, 5, .working)])
        let history = Self.make([heavier, lighter], now: Fixtures.now, calendar: Self.weeks(.monday))
        #expect(history.log.map(\.tag) == [.heavier(.pounds(10)), .same])
    }
}
