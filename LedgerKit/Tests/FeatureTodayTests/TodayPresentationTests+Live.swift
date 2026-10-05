@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// A live workout takes over the card (specification criterion 4; the body's criterion 3; Pete's decision 1,
/// default A). The rule is `TodayPresentation.workoutTakingOver(_:)`.
nonisolated extension TodayPresentationTests {
    /// Lower A of week 1, started `seconds` before `now`.
    static func liveLowerA(
        of program: Program,
        startedBefore seconds: Int,
        now: Date = Fixtures.now
    ) throws -> WorkoutState {
        try TodayFixtures.liveWorkout(
            50,
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: now.addingTimeInterval(-Double(seconds))
        )
    }

    @Test("Today's session, live for three minutes, reads Resume · 3:00 and carries the resume route (criterion 3)")
    func live_todaysSession_showsResumeWithItsStart() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program)
        let live = try Self.liveLowerA(of: program, startedBefore: 180)
        input.session = live
        let card = try #require(TodayPresentation.make(input).card.upNext)
        let resume = TodayModel.Action(title: "Resume · 3:00", route: .resumeWorkout)
        #expect(card.action == .resume(resume, startedAt: live.startedAt))
        #expect(card.eyebrow == "UP NEXT")
        #expect(card.meta == "Week 1 of 8 · ~38 min")
        #expect(card.title == "Lower A — Squat focus")
        #expect(card.rows.map(\.scheme) == ["5 × 5 @ 250", "3 × 8 @ 205", "3 × 12 @ 320", "4 × 12 @ 160"])
    }

    @Test("The label reads the elapsed time as the clock text does, past the hour too")
    func live_elapsed_isClockText() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program)
        input.session = try Self.liveLowerA(of: program, startedBefore: 3665)
        #expect(TodayPresentation.make(input).card.upNext?.action.action.title == "Resume · 1:01:05")
        // A start in the future (a clock that moved) reads zero, never a negative time.
        input.session = try Self.liveLowerA(of: program, startedBefore: -90)
        #expect(TodayPresentation.make(input).card.upNext?.action.action.title == "Resume · 0:00")
    }

    @Test("A workout live for another day than today's takes the card: its name, its exercises, Resume")
    func live_otherDay_takesOverTheCard() throws {
        let program = try TodayFixtures.program()
        // Wednesday is Lower A; Lower B is running, started off-schedule ten minutes ago.
        var input = try TodayFixtures.input(program: program)
        input.session = try TodayFixtures.liveWorkout(
            51,
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerB,
            startedAt: Fixtures.now.addingTimeInterval(-600)
        )
        let model = TodayPresentation.make(input)
        let card = try #require(model.card.upNext)
        #expect(card.title == "Lower B — Hinge focus")
        #expect(card.rows.map(\.name) == ["Deadlift", "Front Squat", "Seated Leg Curl"])
        #expect(card.meta == "Week 1 of 8 · ~31 min")
        #expect(card.action.action == TodayModel.Action(title: "Resume · 10:00", route: .resumeWorkout))
        // The title still says what the calendar says.
        #expect(model.header.title == "Lower A")
    }

    @Test("On a rest day a live workout takes the card too, so Today never loses the way back to it")
    func live_onARestDay_takesOverTheCard() throws {
        let program = try TodayFixtures.program()
        let tuesday = Fixtures.date(2026, 9, 15, hour: 9)
        var input = try TodayFixtures.input(program: program, now: tuesday)
        input.session = try Self.liveLowerA(of: program, startedBefore: 754, now: tuesday)
        let model = TodayPresentation.make(input)
        #expect(model.card.upNext?.action.action.title == "Resume · 12:34")
        #expect(model.card.upNext?.title == "Lower A — Squat focus")
        #expect(model.header.title == "Rest day")
    }

    @Test("A workout begun last night for yesterday's session is still the card after midnight")
    func live_startedYesterday_takesOverTheCard() throws {
        let program = try TodayFixtures.program()
        // Monday's Upper A, started at 23:30; it is now 00:10 on Tuesday.
        var input = try TodayFixtures.input(program: program, now: Fixtures.date(2026, 9, 15, minute: 10))
        input.session = try TodayFixtures.liveWorkout(
            52,
            of: program,
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.upperA,
            startedAt: Fixtures.date(2026, 9, 14, hour: 23, minute: 30)
        )
        let card = try #require(TodayPresentation.make(input).card.upNext)
        #expect(card.title == "Upper A — Push focus")
        #expect(card.action.action.title == "Resume · 40:00")
    }

    @Test("A live workout takes the card after the block and with no program: it shows what the workout holds")
    func live_blockCompleteOrNoProgram_takesOverTheCard() throws {
        let program = try TodayFixtures.program()
        let afterTheBlock = Fixtures.date(2026, 11, 9, minute: 20)
        let live = try TodayFixtures.liveWorkout(
            53,
            of: program,
            weekIndex: 7,
            dayIndex: TodayFixtures.DayIndex.upperB,
            startedAt: Fixtures.date(2026, 11, 8, hour: 23, minute: 50)
        )
        var input = try TodayFixtures.input(program: program, now: afterTheBlock)
        input.session = live
        let complete = TodayPresentation.make(input)
        #expect(complete.card.upNext?.action.action.title == "Resume · 30:00")
        #expect(complete.card.upNext?.meta == "Week 8 of 8 · Deload · ~27 min")
        #expect(complete.header.title == "Today")

        input.program = nil
        let card = try #require(TodayPresentation.make(input).card.upNext)
        #expect(card.title == "Upper B — Pull focus")
        #expect(card.meta == nil)
        #expect(card.rows.count == 4)
        #expect(card.rows.map(\.isDeload) == [true, true, true, true])
        #expect(card.action.action.route == .resumeWorkout)
    }

    @Test("A live workout of another program, or of none, has no week and no estimate")
    func live_notASessionOfTheProgram_hasNoMeta() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program)
        var live = try Self.liveLowerA(of: program, startedBefore: 60)
        live.source = WorkoutSource(
            programID: ProgramID(Fixtures.uuid(77)),
            weekIndex: 0,
            dayTemplateID: program.days[TodayFixtures.DayIndex.lowerA].id
        )
        input.session = live
        #expect(TodayPresentation.make(input).card.upNext?.meta == nil)
        live.source = nil
        input.session = live
        let card = try #require(TodayPresentation.make(input).card.upNext)
        #expect(card.meta == nil)
        #expect(card.title == "Lower A — Squat focus")
    }

    @Test("The live card shows what the workout holds: its name, a swapped exercise, a changed target")
    func live_swappedExercise_showsTheWorkoutsRows() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program, settings: Fixtures.settingsKg)
        var live = try Self.liveLowerA(of: program, startedBefore: 60)
        // The day was renamed in the program after the workout began; the workout keeps the name it started with.
        live.name = "Lower A — Squats"
        live.exercises[0].name = "Front Squat"
        live.exercises[0].targetLoad = .kilograms(100)
        input.session = live
        let card = try #require(TodayPresentation.make(input).card.upNext)
        #expect(card.title == "Lower A — Squats")
        #expect(card.rows.first?.name == "Front Squat")
        #expect(card.rows.first?.scheme == "5 × 5 @ 100")
        #expect(card.rows.map(\.isDeload) == [false, false, false, false])
    }

    @Test("Today never offers Start workout while a workout is live, whatever the day")
    func live_anyDayOfTheBlock_neverOffersStart() throws {
        let program = try TodayFixtures.program()
        for day in -3 ..< 60 {
            let now = Fixtures.date(2026, 9, 14, hour: 10).addingTimeInterval(Double(day) * 86400)
            var input = try TodayFixtures.input(program: program, now: now)
            input.session = try Self.liveLowerA(of: program, startedBefore: 30, now: now)
            let title = TodayPresentation.make(input).card.upNext?.action.action.title
            #expect(title == "Resume · 0:30", "day \(day) of the block")
        }
    }

    @Test("When the live workout finishes, the same update shows Logged, the strip, the tile and the recent row")
    func live_finishes_flipsToLoggedInOneUpdate() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program)
        let live = try Self.liveLowerA(of: program, startedBefore: 1462)
        input.session = live
        #expect(TodayPresentation.make(input).card.kind == "upNext")
        #expect(TodayPresentation.make(input).weekStrip.marks == "P-T-PP-")

        // History has not reported the workout yet: only the session says it is finished.
        input.session = TodayFixtures.finished(live, after: 1462)
        let model = TodayPresentation.make(input)
        #expect(model.card.logged?.elapsed == "24:22")
        #expect(model.card.logged?.action.route == .openWorkout(live.id))
        #expect(model.weekStrip.marks == "P-D-PP-")
        #expect(model.stats.sessions.value == "1")
        #expect(model.recent.rows.map(\.route) == [.openWorkout(live.id)])

        // Then history reports it as well: it is counted once.
        input.weekWorkouts = [TodayFixtures.finished(live, after: 1462)]
        input.recentWorkouts = input.weekWorkouts
        let later = TodayPresentation.make(input)
        #expect(later.stats.sessions.value == "1")
        #expect(later.recent.rows.count == 1)
        let isSame = later == model
        #expect(isSame)
    }

    @Test("A discarded workout is neither live nor logged: the card offers the session again")
    func live_discarded_offersTheSessionAgain() throws {
        let program = try TodayFixtures.program()
        var input = try TodayFixtures.input(program: program)
        var discarded = try Self.liveLowerA(of: program, startedBefore: 600)
        discarded.phase = .discarded
        discarded.endedAt = Fixtures.now
        input.session = discarded
        let model = TodayPresentation.make(input)
        #expect(model.card.upNext?.action.action.title == "Start workout")
        #expect(model.weekStrip.marks == "P-T-PP-")
        #expect(model.recent.rows.isEmpty)
    }
}
