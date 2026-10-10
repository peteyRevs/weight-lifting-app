import Dependencies
@testable import FeatureToday
@testable import FeatureWorkout
import Foundation
@testable import LedgerAppKit
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

// F09 S5 adversarial round 1 (G2): criteria 7 and 10 on Today wired to the launcher. The suite, and what it
// attacks, are in `TodayWiringAdversarialTests.swift`.

extension TodayWiringAdversarialTests {
    // MARK: Criterion 7: one tap, one route, one workout

    @Test("Start workout tapped twice, then again once the cover is up, starts one workout; Today then offers Resume")
    func startWorkout_tappedAgainAndAgain_startsOneWorkout() async throws {
        let app = try App()
        let task = await app.running()
        let start = try #require(app.model?.card.upNextAction)
        #expect(start.title == "Start workout")

        // A double tap within one turn: the store keeps one route, the launcher one request.
        app.today.send(start.route)
        app.today.send(start.route)
        var handed = 0
        app.today.deliverRoute {
            handed += 1
            app.router.resolve($0, workout: app.launcher)
        }
        // A third tap, after the first was handed on and before the launcher has answered.
        app.today.send(start.route)
        app.today.deliverRoute {
            handed += 1
            app.router.resolve($0, workout: app.launcher)
        }
        #expect(handed == 2, "two taps, apart, are two routes")
        #expect(app.launcher.request?.number == 1, "and one request")
        await app.launcher.run()
        #expect(app.launcher.phase == .cover)

        // A fourth, with the cover up (a tap that was on its way when the cover rose).
        await app.tap(start.route)
        #expect(app.launcher.request?.number == 1)
        #expect(await app.starts() == 1)

        // Today follows the session: the same card now resumes, and Resume starts nothing.
        for await isResume in Observations({ app.model?.card.upNextAction?.route == .resumeWorkout }) where isResume {
            break
        }
        app.launcher.send(.coverClosed)
        try await app.tap(#require(app.model?.card.upNextAction).route)
        #expect(app.launcher.phase == .cover)
        #expect(await app.starts() == 1)
        task.cancel()
    }

    // MARK: Criterion 10: a start that is refused is the cover's to show

    @Test(
        "Another day picked while a workout is live asks the launcher's question and starts nothing; Today adds nothing"
    )
    func startOfAnotherDay_whileOneIsLive_isTheLaunchersConflict() async throws {
        let app = try App(now: Fixtures.date(2026, 9, 17, hour: 12))
        let task = await app.running()
        let days = try #require(app.model?.restDayCard?.offSchedule.days)
        #expect(days.count == 4)
        await app.tap(days[0].route)
        #expect(app.launcher.phase == .cover)
        let live = try #require(try await app.fake.current())
        app.launcher.send(.coverClosed)

        // The sheet's list is still the rest day's while the first workout is live: another day is picked.
        await app.tap(days[3].route)
        guard case let .conflict(asked) = app.launcher.phase else {
            Issue.record("the launcher is \(app.launcher.phase)")
            return
        }
        #expect(TodayRoute.startWorkout(program: asked.programID, weekIndex: asked.weekIndex, day: asked.dayTemplateID)
            == days[3].route)
        #expect(try await app.fake.current()?.id == live.id, "the live workout is untouched")
        #expect(await app.starts() == 1)
        #expect(app.router.selectedTab == .today)
        #expect(app.router[path: .today].isEmpty)
        #expect(app.today.pendingRoute == nil)

        // The same day again is that workout, shown, not a second one.
        app.launcher.send(.cancelConflict)
        await app.tap(days[0].route)
        #expect(app.launcher.phase == .cover)
        #expect(await app.starts() == 1)
        task.cancel()
    }

    @Test("A start for a day that has gone since Today drew its button is refused by the launcher; nothing is live")
    func startOfADayThatIsGone_isRefusedByTheLauncher() async throws {
        let app = try App()
        let task = await app.running()
        let start = try #require(app.model?.card.upNextAction)
        task.cancel()
        await task.value

        // The program is deleted while the old model's button is still under the lifter's thumb.
        try await app.stores.programs.delete(Fixtures.seedProgram().id)
        await app.tap(start.route)
        #expect(app.launcher.phase == .failed(.notStarted(.dayNotInProgram)), "\(app.launcher.phase)")
        #expect(try await app.fake.current() == nil)
        #expect(await app.starts() == 0)
        #expect(app.router.selectedTab == .today)
        #expect(app.today.pendingRoute == nil)

        // The launcher's alert dismissed, the next tap is answered again: no state of Today's stands in the way.
        app.launcher.send(.dismissFailure)
        await app.tap(start.route)
        #expect(app.launcher.request?.number == 2)
        #expect(app.launcher.phase == .failed(.notStarted(.dayNotInProgram)))
    }

    @Test("Resume tapped after the workout ended elsewhere opens nothing and leaves the launcher idle")
    func resume_afterTheWorkoutEnded_opensNothing() async throws {
        let app = try App()
        await app.tap(.resumeWorkout)
        #expect(app.launcher.phase == .idle)
        #expect(app.launcher.request?.number == 1)
        #expect(app.router.selectedTab == .today)
        // The launcher is free for the next tap.
        await app.tap(.resumeWorkout)
        #expect(app.launcher.request?.number == 2)
    }
}
