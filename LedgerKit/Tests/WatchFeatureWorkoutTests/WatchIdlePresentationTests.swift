import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The screen before a workout (spec §4.3, §9; F18 criteria 1 and 16, the pure halves). The seed program begins on
/// Monday 2026-08-17: Upper A on Mondays, Lower A on Wednesdays, Upper B on Fridays, Lower B on Saturdays, and a
/// week 8 deload without Lower B. `Fixtures.now` is the Wednesday of week 5.
@Suite("Watch idle presentation", .tags(.watch))
struct WatchIdlePresentationTests {
    static func day(_ month: Int, _ day: Int) -> Date {
        Fixtures.date(2026, month, day, hour: 9)
    }

    @Test("A scheduled day: week label, its name, the plan line and Start; a deload week is marked")
    func idle_scheduledDay() throws {
        let plan = try #require(WatchSample.plan(WatchSample.idle()))
        #expect(plan.weekLabel == "WEEK 5 OF 8" && plan.dayName == "Lower A — Squat focus")
        #expect(plan.planLine == "4 exercises · 15 sets · Back Squat first")
        #expect(plan.start == "Start" && plan.next == nil)
        let deload = try #require(WatchSample.plan(WatchSample.idle(at: Self.day(10, 5))))
        #expect(deload.weekLabel == "WEEK 8 OF 8 · DELOAD" && deload.dayName == "Upper A — Push focus")
        #expect(deload.planLine == "5 exercises · 13 sets · Barbell Bench Press first", "a deload has a set fewer")
    }

    @Test("Plan line: nothing scheduled, logged with its sets and volume, logged earlier, and an empty day")
    func test_planLine_variants() throws {
        let rest = try #require(WatchSample.plan(WatchSample.idle(at: Self.day(9, 17))))
        #expect(rest.dayName == "Rest day" && rest.planLine == "Nothing scheduled today." && rest.start == nil)
        let logged = try WatchSample.idle(workout: WatchSample.loggedLowerA(.pounds(403), reps: 4))
        let loggedPlan = try #require(WatchSample.plan(logged))
        #expect(loggedPlan.planLine == "Logged · 15 sets · 24,180 lb" && loggedPlan.start == nil)
        let one = try WatchSample.idle(workout: WatchSample.loggedLowerA(.pounds(185), reps: 5, sets: 1))
        #expect(WatchSample.plan(one)?.planLine == "Logged · 1 set · 925 lb")
        let earlier = try #require(WatchSample.plan(WatchSample.idle(isTodayLogged: true)))
        #expect(earlier.planLine == "Logged earlier today" && earlier.start == nil && earlier
            .next == "Next: Friday · UB")
        var yesterday = try WatchSample.loggedLowerA(.pounds(185), reps: 5)
        yesterday.startedAt = Fixtures.now.addingTimeInterval(-86400)
        #expect(try WatchSample.plan(WatchSample.idle(workout: yesterday))?.start == "Start", "only today's counts")
        let empty = try WatchSample.idle { $0.days[1].slots = [] }
        #expect(WatchSample.plan(empty)?.planLine == "0 exercises · 0 sets · empty day")
    }

    @Test("Volume has thousands separators: idle in the settings' unit, end and summary in the workout's")
    func test_volume_formattedThousands() throws {
        let workout = try WatchSample.loggedLowerA(.pounds(403), reps: 4)
        let pounds = try WatchSample.idle(workout: workout)
        #expect(WatchSample.plan(pounds)?.planLine == "Logged · 15 sets · 24,180 lb")
        let kilograms = try WatchSample.idle(workout: workout, settings: Fixtures.settingsKg)
        #expect(WatchSample.plan(kilograms)?.planLine == "Logged · 15 sets · 10,968 kg")
        let locale = Fixtures.locale
        #expect(WatchPresentation.end(workout, locale: locale).line == "15 of 15 sets logged · 24,180 lb moved")
        let summary = WatchPresentation.summary(workout, records: [], health: nil, locale: locale)
        #expect(summary.volume == "24,180" && summary.volumeCaption == "LB MOVED")
        var inKilograms = workout
        inKilograms.units = .kg
        #expect(WatchPresentation.end(inKilograms, locale: locale).line == "15 of 15 sets logged · 10,968 kg moved")
        let kgSummary = WatchPresentation.summary(inKilograms, records: [], health: nil, locale: locale)
        #expect(kgSummary.volume == "10,968" && kgSummary.volumeCaption == "KG MOVED")
    }

    @Test("Next: the weekday and tag within the program week, else the later week's number, else nothing")
    func test_nextSessionLine_withinWeek_elseNextWeek() throws {
        #expect(try WatchSample.plan(WatchSample.idle(at: Self.day(9, 17)))?.next == "Next: Friday · UB")
        #expect(try WatchSample.plan(WatchSample.idle(at: Self.day(9, 20)))?.next == "Next: week 6")
        let saturday = try WatchSample.idle(at: Self.day(9, 19), isTodayLogged: true)
        #expect(WatchSample.plan(saturday)?.next == "Next: week 6", "never the week the lifter is in")
        let blockOver = try #require(WatchSample.plan(WatchSample.idle(at: Self.day(10, 10))))
        #expect(blockOver.weekLabel == "WEEK 8 OF 8 · DELOAD" && blockOver.next == nil, "no session left")
        let before = try #require(WatchSample.plan(WatchSample.idle(at: Self.day(8, 10))))
        #expect(before.weekLabel == nil && before.dayName == "Rest day" && before.next == "Next: week 1")
        let after = try #require(WatchSample.plan(WatchSample.idle(at: Self.day(10, 20))))
        #expect(after.weekLabel == nil && after.planLine == "Nothing scheduled today." && after.next == nil)
    }

    @Test("No program on the watch: the title and the app's name in the outlined line")
    func idle_noProgram() throws {
        var input = try WatchSample.idle()
        input.program = nil
        #expect(WatchPresentation.idle(input) == .noProgram(
            title: "No program on watch",
            open: "Open Ledger on iPhone"
        ))
    }
}
