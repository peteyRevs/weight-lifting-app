@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The brief's body criteria 5, 7, 8, 9 and 11 (criterion 10, the recent list, has its own suite).
nonisolated extension TodayWorkedExamplesAdversarialTests {
    /// The seed with nothing on week 1's Saturday: the brief's "a Saturday whose schedule is empty".
    static func seedWithFreeSaturday() throws -> Program {
        var program = try Support.seed()
        program.weeks[0].schedule[.saturday] = nil
        return program
    }

    @Test("Criterion 5: a free Saturday in week 1 reads the rest-day copy and offers all four days")
    func freeSaturday_isARestDayWithTheWholeProgramOffSchedule() throws {
        let program = try Self.seedWithFreeSaturday()
        let now = try Support.moment(Support.civil(2026, 9, 19))
        let model = try TodayPresentation.make(Support.input(program, now: now))
        let card = try Support.rest(model)
        #expect(model.header.date == "Saturday, September 19")
        #expect(model.header.title == "Rest day")
        #expect(card.eyebrow == "SCHEDULED REST")
        #expect(card.title == "No session today")
        #expect(card.body == "Nothing scheduled for Saturday in week 1. Next up is next Monday.")
        let edit = TodayRoute.editWeek(program: program.id, weekIndex: 0)
        #expect(card.editWeek == TodayModel.Action(title: "Edit this week", route: edit))
        #expect(card.offSchedule.title == "Train off-schedule")
        #expect(card.offSchedule.subtitle == "Pick a day from week 1.")
        #expect(card.offSchedule.cancel == "Cancel")
        #expect(card.offSchedule.days.map(\.name) == program.days.map(\.name))
        // Decision #14 by hand: Upper A 2361 s → 39, Lower A 2250 s → 38, Upper B 2220 s → 37, Lower B 1845 s → 31.
        let details = [
            "5 exercises · ~39 min",
            "4 exercises · ~38 min",
            "4 exercises · ~37 min",
            "3 exercises · ~31 min"
        ]
        #expect(card.offSchedule.days.map(\.detail) == details)
        #expect(card.offSchedule.days.map(\.logged) == [nil, nil, nil, nil])
        let routes = program.days.map { TodayRoute.startWorkout(program: program.id, weekIndex: 0, day: $0.id) }
        #expect(card.offSchedule.days.map(\.route) == routes)
    }

    @Test("Criterion 5: a day already done this week reads Logged in the off-schedule list")
    func freeSaturday_marksTheDaysAlreadyDone() throws {
        let program = try Self.seedWithFreeSaturday()
        let monday = try Support.moment(Support.civil(2026, 9, 14), 7)
        let friday = try Support.moment(Support.civil(2026, 9, 18), 7)
        let done = try [
            Support.finished(Support.live(program, week: 0, tag: "UA", number: 1, start: monday)),
            Support.finished(Support.live(program, week: 0, tag: "UB", number: 2, start: friday))
        ]
        let now = try Support.moment(Support.civil(2026, 9, 19))
        let card = try Support.rest(TodayPresentation.make(Support.input(program, now: now, week: done)))
        #expect(card.offSchedule.days.map(\.logged) == ["Logged", nil, "Logged", nil])
    }

    @Test("Criterion 7: the Monday after week 8 shows Block complete, and the rest of Today still fills")
    func afterTheLastWeek_showsBlockComplete() throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 11, 9))
        let earlier = try Support.lifted(number: 3, start: now.addingTimeInterval(-3 * 3600), lifts: [.pounds(100, 10)])
        let input = try Support.input(program, now: now, week: [earlier], recent: [earlier])
        let model = TodayPresentation.make(input)
        let card = try Support.blockComplete(model)
        #expect(card.title == "Block complete")
        #expect(card.body == "8 weeks done. Start the next block from Program.")
        #expect(card.action == TodayModel.Action(title: "Open Program", route: .openProgram))
        #expect(model.header.date == "Monday, November 9")
        #expect(model.header.title == "Today")
        #expect(model.weekStrip.map(\.date) == ["9", "10", "11", "12", "13", "14", "15"])
        #expect(model.weekStrip.map(\.mark) == [.done, .rest, .rest, .rest, .rest, .rest, .rest])
        #expect(model.stats.sessions.value == "1")
        #expect(model.stats.sessions.unit == "/0")
        #expect(model.stats.volume.value == "1.0")
        #expect(model.recent.rows.map(\.route) == [.openWorkout(earlier.id)])
    }

    @Test("Criterion 8: without a program Today shows the No-program card, an unplanned strip and empty tiles")
    func noProgram_showsTheSetUpCard() throws {
        let model = try TodayPresentation.make(Support.input(nil, now: Self.wednesday()))
        let card = try Support.noProgram(model)
        #expect(card.title == "No program yet")
        #expect(card.body == "Set up a program to see your next session here.")
        #expect(card.action == TodayModel.Action(title: "Set up program", route: .setUpProgram))
        #expect(model.header.date == "Wednesday, September 16")
        #expect(model.header.title == "Today")
        #expect(model.weekStrip.map(\.mark) == [.rest, .rest, .today, .rest, .rest, .rest, .rest])
        #expect(model.stats.sessions.value == "0")
        #expect(model.stats.sessions.unit == "/0")
        #expect(model.stats.sessions.caption == "sessions this week")
        #expect(model.stats.volume.value == "0")
        #expect(model.stats.volume.unit == "k")
        #expect(model.stats.volume.caption == "lb moved")
        #expect(model.stats.volume.delta == nil)
        #expect(model.recent.eyebrow == "RECENT")
        #expect(model.recent.rows.isEmpty)
        #expect(model.recent.emptyMessage == "No sessions yet. Your first workout lands here.")
    }

    /// Two finished workouts of this week that moved 12,000 lb and 12,180 lb: the brief's 24,180 lb.
    static func twoWorkouts(moving second: Decimal = 203) throws -> [WorkoutState] {
        let monday = try Support.moment(Support.civil(2026, 9, 14), 7)
        let tuesday = try Support.moment(Support.civil(2026, 9, 15), 7)
        return try [
            Support.lifted(number: 11, start: monday, lifts: [.pounds(200, 30), .pounds(200, 30)]),
            Support.lifted(number: 12, start: tuesday, lifts: [.pounds(second, 30), .pounds(second, 30)])
        ]
    }

    @Test("Criterion 9: 2 of 4 sessions and 24,180 lb after 22,400 lb read 2/4 and 24.2k lb moved · +8%")
    func twoSessionsAndMoreVolume_readTheBriefsTiles() throws {
        let previous = Volume(weight: .pounds(100), reps: Reps(clamping: 224))
        let input = try Support.input(
            Support.seed(),
            now: Self.wednesday(),
            week: Self.twoWorkouts(),
            previous: previous
        )
        let stats = TodayPresentation.make(input).stats
        #expect(stats.sessions.value == "2")
        #expect(stats.sessions.unit == "/4")
        #expect(stats.sessions.caption == "sessions this week")
        #expect(stats.sessions.delta == nil)
        #expect(stats.sessions.accessibilitySummary == "2 of 4 sessions this week")
        #expect(stats.volume.value == "24.2")
        #expect(stats.volume.unit == "k")
        #expect(stats.volume.caption == "lb moved")
        #expect(stats.volume.delta == "+8%")
    }

    @Test("Criterion 9: 21,728 lb after 22,400 lb reads −3% with a real minus sign; no previous week, no change")
    func lessVolume_readsAMinusSign() throws {
        // 12,000 + 2 × 30 × 162.13333… is not a whole load, so the week is 12,000 + 9,728 = 2 × 30 × 162.1333.
        let workouts = try Self.twoWorkouts(moving: Decimal(9728) / 60)
        let previous = Volume(weight: .pounds(100), reps: Reps(clamping: 224))
        let program = try Support.seed()
        let fallen = try Support.input(program, now: Self.wednesday(), week: workouts, previous: previous)
        #expect(TodayPresentation.make(fallen).stats.volume.delta == "\u{2212}3%")
        let first = try Support.input(program, now: Self.wednesday(), week: workouts, previous: nil)
        #expect(TodayPresentation.make(first).stats.volume.delta == nil)
        let afterNothing = try Support.input(program, now: Self.wednesday(), week: workouts, previous: .zero)
        #expect(TodayPresentation.make(afterNothing).stats.volume.delta == nil)
    }

    @Test("Criterion 9 in kilograms: the tile says kg moved and the value converts; the change is the same")
    func kilograms_convertTheVolumeTile() throws {
        let previous = Volume(weight: .pounds(100), reps: Reps(clamping: 224))
        let input = try Support.input(
            Support.seed(),
            now: Self.wednesday(),
            settings: Support.settings(.kg),
            week: Self.twoWorkouts(),
            previous: previous
        )
        let stats = TodayPresentation.make(input).stats
        // 24,180 lb × 0.45359237 = 10,967.86 kg → 11.0 thousand.
        #expect(stats.volume.value == "11.0")
        #expect(stats.volume.unit == "k")
        #expect(stats.volume.caption == "kg moved")
        #expect(stats.volume.delta == "+8%")
    }

    @Test("Criterion 11: with the week starting on Sunday the strip and the sessions run Sunday to Saturday")
    func sundayWeekStart_runsSundayToSaturday() throws {
        let program = try Support.seed()
        let sunday = try Support.moment(Support.civil(2026, 9, 13), 9)
        let nextSunday = try Support.moment(Support.civil(2026, 9, 20), 9)
        let workouts = try [
            Support.lifted(number: 21, start: sunday, lifts: [.pounds(100, 10)]),
            Support.lifted(number: 22, start: nextSunday, lifts: [.pounds(100, 10)])
        ]
        let now = try Self.wednesday()
        let fromSunday = try Support.input(
            program,
            now: now,
            settings: Support.settings(weekStart: .sunday),
            week: workouts
        )
        let model = TodayPresentation.make(fromSunday)
        #expect(model.weekStrip.map(\.weekday) == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(model.weekStrip.map(\.date) == ["13", "14", "15", "16", "17", "18", "19"])
        #expect(model.weekStrip.map(\.mark) == [.done, .planned, .rest, .today, .rest, .planned, .planned])
        #expect(model.stats.sessions.value == "1")
        #expect(model.stats.sessions.unit == "/4")
        let fromMonday = try TodayPresentation.make(Support.input(program, now: now, week: workouts))
        #expect(fromMonday.weekStrip.map(\.date) == ["14", "15", "16", "17", "18", "19", "20"])
        #expect(fromMonday.weekStrip.map(\.mark) == [.planned, .rest, .today, .rest, .planned, .planned, .done])
        #expect(fromMonday.stats.sessions.value == "1")
    }
}
