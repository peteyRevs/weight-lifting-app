@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The Logged card (specification criterion 5; the body's criterion 4; Pete's decision 2, default A). The rule
/// is `TodayPresentation.loggedWorkout(for:_:)`.
nonisolated extension TodayPresentationTests {
    /// Day `dayIndex` of week `weekIndex`, every set done, started at `start` and finished `seconds` later.
    static func finishedSession(
        _ number: Int = 60,
        of program: Program,
        weekIndex: Int,
        dayIndex: Int,
        startedAt start: Date,
        seconds: Int = 1462
    ) throws -> WorkoutState {
        let live = try TodayFixtures.liveWorkout(
            number,
            of: program,
            weekIndex: weekIndex,
            dayIndex: dayIndex,
            startedAt: start
        )
        return TodayFixtures.finished(live, after: seconds)
    }

    /// The model at `now` with `workouts` as the week's finished workouts.
    static func model(_ program: Program, now: Date, weekWorkouts workouts: [WorkoutState]) throws -> TodayModel {
        var input = try TodayFixtures.input(program: program, now: now)
        input.weekWorkouts = workouts
        return TodayPresentation.make(input)
    }

    @Test("Today's session finished today shows Logged with its time, sets, volume and the next session")
    func logged_todaysSessionFinishedToday_showsItsNumbers() throws {
        let program = try TodayFixtures.program()
        let workout = try Self.finishedSession(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: Fixtures.date(2026, 9, 16, hour: 4)
        )
        let model = try Self.model(program, now: Fixtures.now, weekWorkouts: [workout])
        let card = try #require(model.card.logged)
        #expect(card.eyebrow == "LOGGED · WEEK 1")
        #expect(card.elapsed == "24:22")
        #expect(card.title == "Lower A — Squat focus")
        // 5 × 5 × 250 + 3 × 8 × 205 + 3 × 12 × 320 + 4 × 12 × 160.
        #expect(card.stats == "15 of 15 sets · 30,370 lb moved")
        #expect(card.action == TodayModel.Action(title: "View session", route: .openWorkout(workout.id)))
        #expect(card.next == "Next: Friday · UB")
        #expect(model.header.title == "Lower A")
    }

    @Test("The sets line counts the sets done of the set rows, and reads kilograms when the settings do")
    func logged_partlyDoneInKilograms_readsDoneOfTotalAndKilograms() throws {
        let program = try TodayFixtures.program()
        var workout = try Self.finishedSession(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: Fixtures.date(2026, 9, 16, hour: 4)
        )
        // Only the first squat set was done: 250 lb × 5.
        for exercise in workout.exercises.indices {
            for set in workout.exercises[exercise].sets.indices where exercise > 0 || set > 0 {
                workout.exercises[exercise].sets[set].doneAt = nil
            }
        }
        var input = try TodayFixtures.input(program: program, settings: Fixtures.settingsKg)
        input.weekWorkouts = [workout]
        // 1,250 lb is 566.99 kg.
        #expect(TodayPresentation.make(input).card.logged?.stats == "1 of 15 sets · 567 kg moved")
    }

    @Test("Next names the later day of this program week, the next week's number, or nothing when none is left")
    func logged_nextLine_laterThisWeekNextWeekOrNone() throws {
        let program = try TodayFixtures.program()
        // Saturday of week 1 is Lower B; the next session is Monday, in week 2.
        let saturday = try Self.finishedSession(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerB,
            startedAt: Fixtures.date(2026, 9, 19, hour: 8)
        )
        let nextWeek = try Self.model(program, now: Fixtures.date(2026, 9, 19, hour: 10), weekWorkouts: [saturday])
        #expect(nextWeek.card.logged?.next == "Next: week 2")
        #expect(nextWeek.card.logged?.eyebrow == "LOGGED · WEEK 1")

        // Friday of week 8 is the block's last session.
        let friday = try Self.finishedSession(
            of: program,
            weekIndex: 7,
            dayIndex: TodayFixtures.DayIndex.upperB,
            startedAt: Fixtures.date(2026, 11, 6, hour: 8)
        )
        let last = try Self.model(program, now: Fixtures.date(2026, 11, 6, hour: 10), weekWorkouts: [friday])
        let card = try #require(last.card.logged)
        #expect(card.eyebrow == "LOGGED · WEEK 8")
        #expect(card.next == nil)
    }

    @Test("With an empty week ahead, Next names the week the next session is in; with none left, nothing")
    func logged_emptyWeeksAhead_followTheNextSessionNotTheWeekNumber() throws {
        var program = try TodayFixtures.program()
        program.weeks[1].schedule = [:]
        let saturday = try Self.finishedSession(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerB,
            startedAt: Fixtures.date(2026, 9, 19, hour: 8)
        )
        let now = Fixtures.date(2026, 9, 19, hour: 10)
        #expect(try Self.model(program, now: now, weekWorkouts: [saturday]).card.logged?.next == "Next: week 3")
        // Every later week is empty: week 1 is not the block's last week, and still there is no next session.
        for index in 1 ..< program.weeks.count {
            program.weeks[index].schedule = [:]
        }
        let card = try #require(Self.model(program, now: now, weekWorkouts: [saturday]).card.logged)
        #expect(card.next == nil)
    }

    @Test("A next session whose day the program no longer holds leaves the line out")
    func logged_nextDayNotInTheProgram_hasNoNextLine() throws {
        var program = try TodayFixtures.program()
        let wednesday = try Self.finishedSession(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: Fixtures.date(2026, 9, 16, hour: 4)
        )
        program.days.remove(at: TodayFixtures.DayIndex.upperB)
        let card = try #require(Self.model(program, now: Fixtures.now, weekWorkouts: [wednesday]).card.logged)
        #expect(card.next == nil)
    }

    @Test("A session done on another day of the week does not make today's Logged: it is offered again")
    func logged_doneEarlierThisWeek_isOfferedAgain() throws {
        let program = try TodayFixtures.program()
        // Lower A, Wednesday's session, done off-schedule on Tuesday.
        let tuesday = try Self.finishedSession(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: Fixtures.date(2026, 9, 15, hour: 18)
        )
        let model = try Self.model(program, now: Fixtures.now, weekWorkouts: [tuesday])
        #expect(model.card.upNext?.action.action.title == "Start workout")
        #expect(model.weekStrip.marks == "PDT-PP-")
        #expect(model.stats.sessions.value == "1")
    }

    @Test("A workout belongs to the day it started: one begun before midnight is yesterday's (decision #26)")
    func logged_lateNightWorkout_belongsToItsStartDay() throws {
        let program = try TodayFixtures.program()
        // Wednesday's Lower A, started at 23:30 and finished at 00:40 on Thursday.
        let late = try Self.finishedSession(
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: Fixtures.date(2026, 9, 16, hour: 23, minute: 30),
            seconds: 4200
        )
        let beforeMidnight = Fixtures.date(2026, 9, 16, hour: 23, minute: 59)
        #expect(try Self.model(program, now: beforeMidnight, weekWorkouts: [late]).card.kind == "logged")
        var input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 17, hour: 1))
        input.weekWorkouts = [late]
        input.recentWorkouts = [late]
        let thursday = TodayPresentation.make(input)
        #expect(thursday.card.kind == "restDay")
        #expect(thursday.weekStrip.marks == "P-DTPP-")
        #expect(thursday.recent.rows.map(\.meta) == ["Wed · 70 min · 30,370 lb"])
    }

    @Test("Only a finished workout of the same program, week and day makes today Logged")
    func logged_otherSource_isNotTodaysSession() throws {
        let program = try TodayFixtures.program()
        let start = Fixtures.date(2026, 9, 16, hour: 4)
        let lowerA = TodayFixtures.DayIndex.lowerA
        let today = try Self.finishedSession(of: program, weekIndex: 0, dayIndex: lowerA, startedAt: start)
        var otherDay = today
        otherDay.source = TodayFixtures.source(of: program, weekIndex: 0, dayIndex: TodayFixtures.DayIndex.lowerB)
        var otherWeek = today
        otherWeek.source = TodayFixtures.source(of: program, weekIndex: 1, dayIndex: lowerA)
        var otherProgram = today
        otherProgram.source = WorkoutSource(
            programID: ProgramID(Fixtures.uuid(78)),
            weekIndex: 0,
            dayTemplateID: program.days[lowerA].id
        )
        var adHoc = today
        adHoc.source = nil
        var stillLive = today
        stillLive.phase = .live
        for workout in [otherDay, otherWeek, otherProgram, adHoc, stillLive] {
            let model = try Self.model(program, now: Fixtures.now, weekWorkouts: [workout])
            #expect(model.card.kind == "upNext", "source \(String(describing: workout.source)), \(workout.phase)")
        }
        #expect(try Self.model(program, now: Fixtures.now, weekWorkouts: [today]).card.kind == "logged")
    }

    @Test(
        "Of two finished today for the same session the card shows the one that started last, in any order",
        arguments: [false, true]
    )
    func logged_twiceToday_showsTheNewest(newestFirst: Bool) throws {
        let program = try TodayFixtures.program()
        let lowerA = TodayFixtures.DayIndex.lowerA
        let first = try Self.finishedSession(
            61,
            of: program,
            weekIndex: 0,
            dayIndex: lowerA,
            startedAt: Fixtures.date(2026, 9, 16, hour: 1)
        )
        let second = try Self.finishedSession(
            62,
            of: program,
            weekIndex: 0,
            dayIndex: lowerA,
            startedAt: Fixtures.date(2026, 9, 16, hour: 4),
            seconds: 600
        )
        // The input promises no order (criterion 13): oldest first gives the same card as newest first.
        let week = newestFirst ? [second, first] : [first, second]
        let model = try Self.model(program, now: Fixtures.now, weekWorkouts: week)
        #expect(model.card.logged?.action.route == .openWorkout(second.id))
        #expect(model.card.logged?.elapsed == "10:00")
        #expect(model.stats.sessions.value == "2")
    }

    @Test("Next follows the program week, not the strip: it never names the week the lifter is in (criterion 15)")
    func logged_nextLine_followsTheProgramWeekNotTheStrip() throws {
        // The week starts on Sunday, and week 1 trains on its Sunday (09-20), the first day of the next strip.
        var settings = Fixtures.settingsLb
        settings.weekStart = .sunday
        var program = try TodayFixtures.program()
        program.weeks[0].schedule[.sunday] = program.days[TodayFixtures.DayIndex.lowerB].id
        let lowerB = TodayFixtures.DayIndex.lowerB
        // Logged on Saturday 09-19: Sunday's session is off the strip and in the same program week.
        var saturday = try TodayFixtures.input(
            program: program,
            now: Fixtures.date(2026, 9, 19, hour: 10),
            settings: settings
        )
        saturday.weekWorkouts = try [
            Self.finishedSession(
                of: program,
                weekIndex: 0,
                dayIndex: lowerB,
                startedAt: Fixtures.date(2026, 9, 19, hour: 8)
            )
        ]
        #expect(TodayPresentation.make(saturday).card.logged?.next == "Next: Sunday · LB")
        // Logged on Sunday 09-20: Monday's session is on the same strip and in program week 2.
        var sunday = try TodayFixtures.input(
            program: program,
            now: Fixtures.date(2026, 9, 20, hour: 10),
            settings: settings
        )
        sunday.weekWorkouts = try [
            Self.finishedSession(
                of: program,
                weekIndex: 0,
                dayIndex: lowerB,
                startedAt: Fixtures.date(2026, 9, 20, hour: 8)
            )
        ]
        let card = try #require(TodayPresentation.make(sunday).card.logged)
        #expect(card.eyebrow == "LOGGED · WEEK 1")
        #expect(card.next == "Next: week 2")
    }
}
