@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: which card, case by case (S3 criteria 4 and 5), with expectations written by hand. The
/// seed program begins on Monday 2026-09-14; Wednesday 09-16 is Lower A in week 1 and Tuesday 09-15 is a rest day.
@Suite("Adversarial F09 S3 · which card, case by case", .tags(.feature))
nonisolated struct TodayCardAdversarialTests {
    typealias Support = TodayAdversarial

    static func noon(_ day: Int, month: Int = 9) throws -> Date {
        try Support.moment(Support.civil(2026, month, day))
    }

    /// Lower A of week 1, finished, started on `day` at `hour`.
    static func lowerA(
        _ program: Program,
        number: Int,
        day: Int,
        hour: Int,
        seconds: Int = 3600
    ) throws -> WorkoutState {
        let start = try Support.moment(Support.civil(2026, 9, day), hour)
        return try Support.finished(
            Support.live(program, week: 0, tag: "LA", number: number, start: start),
            after: seconds
        )
    }

    @Test("A workout live for another day takes the card on a scheduled day; the title stays today's")
    func liveForAnotherDay_takesTheCard() throws {
        let program = try Support.seed()
        let now = try Self.noon(16)
        let live = try Support.live(program, week: 0, tag: "UB", number: 5, start: now.addingTimeInterval(-61))
        let model = try TodayPresentation.make(Support.input(program, now: now, session: live))
        let card = try Support.upNext(model)
        #expect(card.action == .resume(.init(title: "Resume · 1:01", route: .resumeWorkout), startedAt: live.startedAt))
        #expect(card.title == "Upper B — Pull focus")
        #expect(card.rows.map(\.name) == ["Weighted Pull-Up", "Overhead Press", "Barbell Row", "Barbell Curl"])
        #expect(card.rows.map(\.scheme) == ["4 × 6 @ 35", "4 × 6 @ 115", "3 × 10 @ 155", "3 × 12 @ 75"])
        #expect(model.header.title == "Lower A")
        #expect(model.weekStrip.map(\.mark) == [.planned, .rest, .today, .rest, .planned, .planned, .rest])
    }

    @Test("A live workout takes the card on a rest day, after the block and without a program", arguments: [
        "rest day", "after the block", "no program"
    ])
    func liveWorkout_takesTheCardWhateverTheCalendarSays(_ situation: String) throws {
        let program = try Support.seed()
        let now = try situation == "after the block" ? Self.noon(9, month: 11) : Self.noon(15)
        let live = try Support.live(program, week: 0, tag: "LA", number: 5, start: now.addingTimeInterval(-3725))
        let active = situation == "no program" ? nil : program
        let model = try TodayPresentation.make(Support.input(active, now: now, session: live))
        let card = try Support.upNext(model)
        #expect(card.action == .resume(
            .init(title: "Resume · 1:02:05", route: .resumeWorkout),
            startedAt: live.startedAt
        ))
        #expect(card.title == "Lower A — Squat focus")
        #expect(card.rows.count == 4)
        #expect(model.header.title == (situation == "rest day" ? "Rest day" : "Today"))
    }

    @Test("Today's session done yesterday is offered again today, and yesterday is marked done")
    func sessionDoneYesterday_isOfferedAgain() throws {
        let program = try Support.seed()
        let yesterday = try Self.lowerA(program, number: 1, day: 15, hour: 18)
        let model = try TodayPresentation.make(Support.input(program, now: Self.noon(16), week: [yesterday]))
        let card = try Support.upNext(model)
        let lowerA = try Support.day("LA", in: program)
        #expect(card.action.action.route == .startWorkout(program: program.id, weekIndex: 0, day: lowerA.id))
        #expect(card.action.action.title == "Start workout")
        #expect(model.weekStrip.map(\.mark) == [.planned, .done, .today, .rest, .planned, .planned, .rest])
        #expect(model.stats.sessions.value == "1")
    }

    @Test("Today's session done twice today shows the later one, whichever comes first in the input", arguments: [
        false, true
    ])
    func sessionDoneTwice_showsTheLaterOne(_ newestFirst: Bool) throws {
        let program = try Support.seed()
        let morning = try Self.lowerA(program, number: 1, day: 16, hour: 6, seconds: 600)
        let later = try Self.lowerA(program, number: 2, day: 16, hour: 9, seconds: 1462)
        let week = newestFirst ? [later, morning] : [morning, later]
        let now = try Support.moment(Support.civil(2026, 9, 16), 11)
        let model = try TodayPresentation.make(Support.input(program, now: now, week: week))
        let card = try Support.logged(model)
        #expect(card.action.route == .openWorkout(later.id))
        #expect(card.elapsed == "24:22")
        #expect(model.stats.sessions.value == "2")
        #expect(model.weekStrip.count { $0.mark == .done } == 1)
    }

    @Test(
        "A workout of the same day for another program, another week or another day does not log today's",
        arguments: [
            "another program", "another week", "another day", "no program"
        ]
    )
    func workoutOfAnotherSource_doesNotLogToday(_ kind: String) throws {
        let program = try Support.seed()
        let lowerA = try Support.day("LA", in: program)
        let upperB = try Support.day("UB", in: program)
        let source: WorkoutSource? = switch kind {
        case "another program": WorkoutSource(
                programID: TodayScenario.otherProgram,
                weekIndex: 0,
                dayTemplateID: lowerA.id
            )
        case "another week": WorkoutSource(programID: program.id, weekIndex: 1, dayTemplateID: lowerA.id)
        case "another day": WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: upperB.id)
        default: nil
        }
        let start = try Support.moment(Support.civil(2026, 9, 16), 6)
        let done = try Support.lifted(number: 3, start: start, lifts: [.pounds(100, 5)], source: source)
        let model = try TodayPresentation.make(Support.input(program, now: Self.noon(16), week: [done]))
        let card = try Support.upNext(model)
        #expect(card.action.action.route == .startWorkout(program: program.id, weekIndex: 0, day: lowerA.id))
        #expect(model.weekStrip[2].mark == .done)
        #expect(model.stats.sessions.value == "1")
    }
}

// MARK: - The session's own workout

nonisolated extension TodayCardAdversarialTests {
    @Test("The session's finished workout that history also reports is counted once")
    func finishedSessionAlsoInHistory_isCountedOnce() throws {
        let program = try Support.seed()
        let done = try Self.lowerA(program, number: 4, day: 16, hour: 6)
        let input = try Support.input(program, now: Self.noon(16), week: [done], recent: [done], session: done)
        let model = TodayPresentation.make(input)
        #expect(try Support.logged(model).action.route == .openWorkout(done.id))
        #expect(model.stats.sessions.value == "1")
        #expect(model.stats.volume.value == "30.4")
        #expect(model.recent.rows.map(\.route) == [.openWorkout(done.id)])
    }

    @Test("The session's finished workout that history does not report yet is in the strip, the tiles and the list")
    func finishedSessionNotYetInHistory_isShownEverywhere() throws {
        let program = try Support.seed()
        let done = try Self.lowerA(program, number: 4, day: 16, hour: 6, seconds: 1462)
        let model = try TodayPresentation.make(Support.input(program, now: Self.noon(16), session: done))
        #expect(try Support.logged(model).stats == "15 of 15 sets · 30,370 lb moved")
        #expect(model.weekStrip[2].mark == .done)
        #expect(model.stats.sessions.value == "1")
        #expect(model.stats.volume.value == "30.4")
        #expect(model.recent.rows.map(\.route) == [.openWorkout(done.id)])
        #expect(model.recent.rows.map(\.meta) == ["Today · 24:22 · 30,370 lb"])
        #expect(model.recent.emptyMessage == nil)
    }

    @Test("A discarded session, and rows of history that are not finished, count for nothing")
    func unfinishedWorkouts_countForNothing() throws {
        let program = try Support.seed()
        var discarded = try Self.lowerA(program, number: 4, day: 16, hour: 6)
        discarded.phase = .discarded
        var stray = try Self.lowerA(program, number: 5, day: 16, hour: 7)
        stray.phase = .live
        stray.endedAt = nil
        let input = try Support.input(program, now: Self.noon(16), week: [stray, discarded], session: discarded)
        let model = TodayPresentation.make(input)
        #expect(try Support.upNext(model).action.action.title == "Start workout")
        #expect(model.weekStrip[2].mark == .today)
        #expect(model.stats.sessions.value == "0")
        #expect(model.stats.volume.value == "0")
    }

    @Test("A workout that goes live after today's session was logged takes the card back")
    func liveAfterLogged_takesTheCard() throws {
        let program = try Support.seed()
        let done = try Self.lowerA(program, number: 4, day: 16, hour: 6)
        let now = try Self.noon(16)
        let live = try Support.live(program, week: 0, tag: "UB", number: 5, start: now.addingTimeInterval(-9))
        let model = try TodayPresentation.make(Support.input(program, now: now, week: [done], session: live))
        #expect(try Support.upNext(model).action.action == .init(title: "Resume · 0:09", route: .resumeWorkout))
        #expect(model.weekStrip[2].mark == .done)
    }

    @Test("A live workout whose start is still ahead of the clock reads Resume · 0:00")
    func liveStartedInTheFuture_readsZero() throws {
        let program = try Support.seed()
        let now = try Self.noon(16)
        let live = try Support.live(program, week: 0, tag: "LA", number: 5, start: now.addingTimeInterval(40))
        let card = try Support.upNext(TodayPresentation.make(Support.input(program, now: now, session: live)))
        #expect(card.action.action.title == "Resume · 0:00")
    }
}
