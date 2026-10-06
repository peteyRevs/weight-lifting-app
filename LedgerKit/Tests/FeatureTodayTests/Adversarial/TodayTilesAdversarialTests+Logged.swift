@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The Logged card's sets and volume against its workout, and the off-schedule list's marks against the
/// program week, when that week is not the strip's.
nonisolated extension TodayTilesAdversarialTests {
    /// Upper B of week 1 finished on Friday 2026-09-18 with its first `done` sets ticked, and the card it gives.
    static func upperBLogged(done: Int, units: Units) throws -> TodayModel.Logged {
        let program = try Support.seed()
        let start = try Support.moment(Support.civil(2026, 9, 18), 6)
        let workout = try Support.finished(
            Support.live(program, week: 0, tag: "UB", number: 8, start: start),
            after: 3725,
            done: done
        )
        let input = try Support.input(
            program,
            now: start.addingTimeInterval(7200),
            settings: Support.settings(units),
            week: [workout]
        )
        return try Support.logged(TodayPresentation.make(input))
    }

    @Test("The Logged card counts the drop set among its sets and only done sets in its volume")
    func loggedCard_countsEverySetRowAndOnlyDoneVolume() throws {
        // Pull-up 4×6×35 + press 4×6×115 + row 3×10×155 + curl 3×12×75 + its drop set 12×65 = 11,730 lb, 15 rows.
        let whole = try Self.upperBLogged(done: .max, units: .lb)
        #expect(whole.stats == "15 of 15 sets · 11,730 lb moved")
        #expect(whole.elapsed == "1:02:05")
        // The first nine: 840 + 2,760 + one row set of 1,550 = 5,150 lb = 2,336.0 kg.
        #expect(try Self.upperBLogged(done: 9, units: .lb).stats == "9 of 15 sets · 5,150 lb moved")
        #expect(try Self.upperBLogged(done: 9, units: .kg).stats == "9 of 15 sets · 2,336 kg moved")
        #expect(try Self.upperBLogged(done: 0, units: .lb).stats == "0 of 15 sets · 0 lb moved")
        #expect(try Self.upperBLogged(done: 1, units: .kg).stats == "1 of 15 sets · 95 kg moved")
    }

    @Test("A logged workout of one set row reads set in the singular, and one of none reads 0 of 0 sets", arguments: [
        0, 1, 2
    ])
    func loggedCard_countsSetsInTheSingular(_ rows: Int) throws {
        let program = try Support.seed()
        let lowerA = try Support.day("LA", in: program)
        let start = try Support.moment(Support.civil(2026, 9, 16), 6)
        let source = WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: lowerA.id)
        let lifts = (0 ..< rows).map { Support.Lift(weight: .pounds(100), reps: 5, isDone: $0 == 0) }
        let workout = try Support.lifted(number: 9, start: start, seconds: 59, lifts: lifts, source: source)
        let card = try Support.logged(TodayPresentation.make(Support.input(
            program,
            now: Self.wednesday(),
            week: [workout]
        )))
        let expected = ["0 of 0 sets · 0 lb moved", "1 of 1 set · 500 lb moved", "1 of 2 sets · 500 lb moved"]
        #expect(card.stats == expected[rows])
        #expect(card.elapsed == "0:59")
    }

    @Test("Off-schedule marks follow the program week; the tiles and the strip follow the strip's seven days")
    func straddlingWeek_keepsTheTwoWeeksApart() throws {
        // The block begins on Wednesday 09-16, so week 1 runs to Tuesday 09-22, a rest day in the next strip.
        let program = try Support.seed(start: Support.civil(2026, 9, 16))
        let done = try [("LA", 16), ("UB", 18), ("UA", 21)].enumerated().map { index, session in
            let start = try Support.moment(Support.civil(2026, 9, session.1), 7)
            return try Support.finished(Support.live(
                program,
                week: 0,
                tag: session.0,
                number: 80 + index,
                start: start
            ))
        }
        let now = try Support.moment(Support.civil(2026, 9, 22), 12)
        let model = try TodayPresentation.make(Support.input(program, now: now, week: done))
        let card = try Support.rest(model)
        #expect(card.offSchedule.days.map(\.logged) == ["Logged", "Logged", "Logged", nil])
        #expect(card.body == "Nothing scheduled for Tuesday in week 1. Next up is next Wednesday.")
        // Only Monday's Upper A started in the strip (09-21 … 09-27): 5×5×180 + 3×10×50 + 4×8×65 + 3×12×100
        // + 3×15×12.5 = 12,242.5 lb.
        #expect(model.stats.sessions.value == "1")
        #expect(model.stats.sessions.unit == "/4")
        #expect(model.stats.volume.value == "12.2")
        #expect(model.weekStrip.map(\.date) == ["21", "22", "23", "24", "25", "26", "27"])
        #expect(model.weekStrip.count { $0.mark == .done } == 1)
        #expect(model.weekStrip[0].mark == .done)
        #expect(model.weekStrip[1].mark == .today)
    }

    @Test("Only a finished workout of this program, this week and that day marks a day Logged in the list")
    func offScheduleMarks_needTheSameProgramWeekAndDay() throws {
        let program = try Support.seed()
        let start = try Support.moment(Support.civil(2026, 9, 14), 7)
        let sources = [
            WorkoutSource(programID: program.id, weekIndex: 1, dayTemplateID: program.days[0].id),
            WorkoutSource(programID: TodayScenario.otherProgram, weekIndex: 0, dayTemplateID: program.days[1].id),
            WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: program.days[3].id)
        ]
        var workouts = try sources.enumerated().map { index, source in
            try Support.lifted(number: 90 + index, start: start, lifts: [.pounds(100, 10)], source: source)
        }
        var unfinished = try Support.live(program, week: 0, tag: "UB", number: 99, start: start)
        unfinished.phase = .discarded
        workouts.append(unfinished)
        let now = try Support.moment(Support.civil(2026, 9, 15))
        let card = try Support.rest(TodayPresentation.make(Support.input(program, now: now, week: workouts)))
        #expect(card.offSchedule.days.map(\.logged) == [nil, nil, nil, "Logged"])
    }
}
