import Foundation
@testable import LedgerDomain
import Testing

/// F12 S2: `ExerciseHistory.make`, the pure fold of one exercise's sessions (criteria 4–7, N9, N10). Every
/// session here is one workout of bench, numbered so that a larger number is a later workout.
@Suite("ExerciseHistory", .tags(.domain))
struct ExerciseHistoryTests {
    /// Stats weeks from Monday, in UTC.
    static let monday = WeekCalendar(startDate: .unixEpoch, weekStart: .monday, calendar: Fixtures.calendar)

    /// A set as the tests write it: pounds, reps and kind.
    typealias Spec = (pounds: Decimal, reps: Int, kind: SetKind) // swiftlint:disable:this large_tuple

    static func session(
        _ number: Int,
        on date: Date,
        _ sets: [Spec]
    ) -> ExerciseSession {
        ExerciseSession(
            workoutID: WorkoutID(Fixtures.uuid(4000 + number)),
            startedAt: date,
            sets: sets.enumerated().map { place, set in
                Fixtures.set(number * 20 + place, pounds: set.pounds, reps: set.reps, kind: set.kind)
            }
        )
    }

    /// `count` working sets of `reps` × `pounds`.
    static func straight(_ count: Int, _ pounds: Decimal, _ reps: Int) -> [Spec] {
        Array(repeating: (pounds, reps, .working), count: count)
    }

    static func make(
        _ sessions: [ExerciseSession],
        records: Set<WorkoutID> = [],
        now: Date = Fixtures.now,
        calendar: WeekCalendar = monday
    ) -> ExerciseHistory {
        ExerciseHistory.make(sessions: sessions, records: records, now: now, calendar: calendar)
    }

    /// The records `PersonalRecords.detect` finds in each session, judged in time order against the bests before
    /// it: what `StatsQueries.personalRecords` stores (decision #27).
    static func records(_ sessions: [ExerciseSession]) throws -> Set<WorkoutID> {
        var bests = PersonalRecords.Bests()
        var found: Set<WorkoutID> = []
        for session in sessions.reversed() {
            let workout = try WorkoutState(
                id: session.workoutID, source: nil, name: "", tag: "", isDeload: false,
                exercises: [Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: session.sets)],
                cursor: nil, startedAt: session.startedAt, phase: .finished, originDevice: Fixtures.deviceID
            )
            if !PersonalRecords.detect(workout: workout, against: bests, now: session.startedAt).isEmpty {
                found.insert(session.workoutID)
            }
            bests.include(workout)
        }
        return found
    }

    // MARK: Criteria 4 and 6

    @Test("4. The estimate is Brzycki of the best set up to 12 reps: 195 × 5 is 219; the best set is 195 × 5")
    func e1RM_isBrzyckiOfTheBestSetUpTo12Reps() {
        let history = Self.make([
            Self.session(2, on: Fixtures.now, Self.straight(5, 195, 5)),
            Self.session(1, on: Fixtures.date(2026, 9, 9), Self.straight(5, 185, 5) + [(100, 15, .working)])
        ])
        #expect(history.e1RM?.wholeValue(in: .lb) == 219)
        #expect(history.bestSet == BestSet(weight: .pounds(195), reps: Reps(clamping: 5)))
        #expect(history.sessions == 2)
    }

    @Test("6. A best of 100 × 15 has no estimate (reps over 12), and is still the best set")
    func e1RM_ignoresRepsOver12() {
        let history = Self.make([Self.session(1, on: Fixtures.now, Self.straight(3, 100, 15))])
        #expect(history.e1RM == nil)
        #expect(history.bestSet == BestSet(weight: .pounds(100), reps: Reps(clamping: 15)))
        #expect(history.weeks.allSatisfy { $0.e1RM == nil })
    }

    @Test("Of two sets as heavy, the best set is the one with more reps")
    func bestSet_ofTwoAsHeavy_isTheOneWithMoreReps() {
        let history = Self.make([Self.session(
            1,
            on: Fixtures.now,
            [(200, 3, .working), (200, 5, .added), (200, 4, .working)]
        )])
        #expect(history.bestSet == BestSet(weight: .pounds(200), reps: Reps(clamping: 5)))
    }

    @Test("Warm-ups and drop sets show in the log and never count toward a best; a session of warm-ups counts")
    func warmupsAndDrops_showButNeverCount() {
        let warmups = Self.session(2, on: Fixtures.now, [(95, 5, .warmup), (135, 3, .warmup)])
        let drop = Self.session(
            1,
            on: Fixtures.date(2026, 9, 9),
            [(300, 2, .warmup), (180, 5, .working), (250, 3, .drop)]
        )
        let history = Self.make([warmups, drop])
        #expect(history.bestSet == BestSet(weight: .pounds(180), reps: Reps(clamping: 5)))
        #expect(history.e1RM == OneRepMax.brzycki(weight: .pounds(180), reps: Reps(clamping: 5)))
        #expect(history.sessions == 2)
        #expect(history.log.map(\.sets.count) == [2, 3])
        #expect(history.log.map(\.tag) == [.same, .same], "warm-ups only: no working set to compare")
    }

    @Test("5. With no working or added set there is no estimate, no best and no week with a value")
    func noCountedSet_hasNothing() {
        let history = Self.make([])
        #expect(history.e1RM == nil && history.bestSet == nil && history.sessions == 0 && history.log.isEmpty)
        #expect(history.weeks.count == 8 && history.weeks.allSatisfy { $0.e1RM == nil })
    }

    // MARK: Weeks (criteria 4, 5; decision #15)

    @Test("5. Eight weeks end with the current one; a week with no session has no value and keeps its place")
    func weeks_eightEndingNow_emptyWeeksNil() {
        // Wednesday 2026-09-16: the current Monday week starts on the 14th; W1 starts on 2026-07-27.
        let logged = [0, 1, 3, 4, 6, 7]
        let pounds = { (back: Int) in Decimal(200 - 5 * back) }
        let sessions = logged.map { back in
            Self.session(
                back,
                on: Fixtures.now.addingTimeInterval(-Double(back) * 7 * 86400),
                Self.straight(3, pounds(back), 5)
            )
        } + [Self.session(9, on: Fixtures.date(2026, 7, 26, hour: 23), Self.straight(1, 400, 1))]
        let weeks = Self.make(sessions).weeks
        #expect(weeks.map(\.start) == (0 ..< 8)
            .map { Fixtures.date(2026, 7, 27).addingTimeInterval(Double($0) * 7 * 86400) })
        let expected = (0 ..< 8).reversed().map { back in
            logged.contains(back) ? OneRepMax.brzycki(weight: .pounds(pounds(back)), reps: Reps(clamping: 5)) : nil
        }
        #expect(weeks.map(\.e1RM) == expected, "W3 and W6 are empty; the Sunday before W1 is not in it")
    }

    @Test("Weeks start on the lifter's first day: from Sunday, a Sunday session opens the current week")
    func weeks_weekStartSunday() {
        let sunday = WeekCalendar(startDate: .unixEpoch, weekStart: .sunday, calendar: Fixtures.calendar)
        let session = Self.session(1, on: Fixtures.date(2026, 9, 13, hour: 9), Self.straight(1, 200, 5))
        #expect(Self.make([session], calendar: sunday).weeks.last?.e1RM != nil)
        #expect(Self.make([session], calendar: sunday).weeks.last?.start == Fixtures.date(2026, 9, 13))
        #expect(Self.make([session]).weeks.last?.e1RM == nil, "from Monday it is the week before's")
        let byDay = ExerciseHistory.make(
            sessions: [session], records: [], now: Fixtures.now, weekStart: .sunday, calendar: Fixtures.calendar
        )
        #expect(byDay == Self.make([session], calendar: sunday), "the week start and calendar make the same weeks")
    }

    @Test("A week across the change of clocks is one week: a session late on its last day is in it")
    func weeks_acrossDaylightSaving() throws {
        var newYork = Fixtures.calendar
        newYork.timeZone = try Fixtures.zone("America/New_York")
        let weeks = WeekCalendar(startDate: .unixEpoch, weekStart: .monday, calendar: newYork)
        // 2026-11-01 is the fall-back Sunday; its week (Oct 26 – Nov 1) has 169 hours.
        let late = Self.session(
            1,
            on: Fixtures.date(2026, 11, 1, hour: 23, minute: 30, in: newYork.timeZone),
            Self.straight(1, 200, 5)
        )
        let now = Fixtures.date(2026, 11, 4, hour: 12, in: newYork.timeZone)
        let history = Self.make([late], now: now, calendar: weeks)
        #expect(history.weeks.map { $0.e1RM != nil } == [false, false, false, false, false, false, true, false])
        #expect(history.weeks[6].start == Fixtures.date(2026, 10, 26, in: newYork.timeZone))
    }
}

extension ExerciseHistoryTests {
    // MARK: Tags (criterion 7, N10)

    @Test("7. Jun 24 175 × 6, then Jul 22, Jul 29, Aug 5 and Aug 12: —, —, +5 lb, —, PR from the newest down")
    func tags_criterion7_prUpSame() throws {
        let sessions = [
            Self.session(5, on: Fixtures.date(2026, 8, 12), Self.straight(5, 180, 5)),
            Self.session(4, on: Fixtures.date(2026, 8, 5), Self.straight(4, 175, 5) + [(175, 4, .working)]),
            Self.session(3, on: Fixtures.date(2026, 7, 29), Self.straight(4, 175, 5)),
            Self.session(2, on: Fixtures.date(2026, 7, 22), Self.straight(5, 170, 5)),
            Self.session(1, on: Fixtures.date(2026, 6, 24), Self.straight(1, 175, 6))
        ]
        let records = try Self.records(sessions)
        #expect(records == [sessions[0].workoutID], "only Aug 12 beats Jun 24's 175 × 6")
        let history = Self.make(sessions, records: records)
        #expect(history.log.map(\.tag) == [.record, .same, .heavier(.pounds(5)), .same, .same])
        #expect(history.log.map(\.date) == sessions.map(\.startedAt))
        #expect(history.log.map(\.workoutID) == sessions.map(\.workoutID))
    }

    @Test("A first session is a baseline, and a session with a record is PR whatever its weight")
    func tags_firstSessionIsSame_recordWins() {
        let first = Self.session(1, on: Fixtures.date(2026, 9, 1), Self.straight(1, 200, 5))
        #expect(Self.make([first]).log.map(\.tag) == [.same])
        let lighter = Self.session(2, on: Fixtures.date(2026, 9, 8), Self.straight(1, 150, 12))
        #expect(Self.make([lighter, first], records: [lighter.workoutID]).log.map(\.tag) == [.record, .same])
    }

    /// N19 (S3): the step compares the sets that count toward bests, decision #25's working and added sets, as the
    /// records do; it replaced S2's working sets alone.
    @Test("+{step} compares the sets that count toward bests: an added set counts, a warm-up or a drop set does not")
    func tags_compareCountedSetsOnly() {
        let before = Self.session(1, on: Fixtures.date(2026, 9, 1), Self.straight(3, 200, 5))
        let added = Self.session(
            2,
            on: Fixtures.date(2026, 9, 8),
            Self.straight(3, 200, 5) + [(210, 3, .added), (300, 1, .warmup), (305, 8, .drop)]
        )
        let higher = Self.session(3, on: Fixtures.date(2026, 9, 15), Self.straight(3, 207.5, 5))
        #expect(Self.make([higher, added, before]).log.map(\.tag) == [.same, .heavier(.pounds(10)), .same])
    }

    @Test("N19: +{step} passes over sessions with no set that counts, which are themselves —")
    func tags_sessionsWithoutCountedSets_arePassedOver() {
        let first = Self.session(1, on: Fixtures.date(2026, 9, 1), Self.straight(3, 200, 5))
        let warmups = Self.session(2, on: Fixtures.date(2026, 9, 4), [(135, 5, .warmup), (185, 3, .warmup)])
        let drops = Self.session(3, on: Fixtures.date(2026, 9, 6), [(150, 10, .drop)])
        let heavier = Self.session(4, on: Fixtures.date(2026, 9, 8), Self.straight(3, 205, 5))
        let lighter = Self.session(5, on: Fixtures.date(2026, 9, 10), [(95, 5, .warmup)] + Self.straight(3, 190, 5))
        let history = Self.make([lighter, heavier, drops, warmups, first])
        #expect(history.log.map(\.tag) == [.same, .heavier(.pounds(5)), .same, .same, .same])
        let onlyWarmups = Self.make([warmups])
        #expect(onlyWarmups.log.map(\.tag) == [.same])
    }
}
