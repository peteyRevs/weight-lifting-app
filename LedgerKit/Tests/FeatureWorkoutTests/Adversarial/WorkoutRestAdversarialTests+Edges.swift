import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// G2, F10 S6: single cases the seeded walk does not reach. Round 1's three findings are at the end:
/// F10-S6-1 is pinned as built (ruling 20), F10-S6-2 and -3 were fixed in fix round 1 and hold.
extension WorkoutRestAdversarialTests {
    static func resting() async throws -> (cover: RestCover, rows: [LoggedSet]) {
        let running = try Fixtures.seedSession()
        let cover = try await RestCover(running)
        await cover.tap(.log(exerciseIndex: 0, setID: running.exercises[0].sets[0].id))
        return (cover, running.exercises[0].sets)
    }

    // MARK: Held

    @Test("Two waits on the same rest (a task started again before the first ended) are one buzz at zero")
    func twoWaits_oneBuzz() async throws {
        let (cover, _) = try await Self.resting()
        let second = Task { [store = cover.store] in await store.keepRestTime() }
        await giveWay()
        await cover.run(150)
        await second.value
        #expect(await cover.played() == [.setLogged, .restOver])
        await cover.close()
    }

    /// Fix round 1 (sanctioned edit; ruling 16 inverts the expectation): a tick changes the panel alone.
    @Test(
        "A second of a rest is one change of the rest panel and none of the screen's model"
    )
    func eachSecond_oneChange_thePageUntouched() async throws {
        let (cover, _) = try await Self.resting()
        guard case let .workout(before) = cover.store.model else {
            Issue.record("no workout on screen")
            return
        }
        let (changes, watching) = Self.counting { [store = cover.store] in store.model }
        let (panelChanges, watchingThePanel) = Self.counting { [store = cover.store] in store.restPanel }
        await giveWay()
        changes.setValue(0)
        panelChanges.setValue(0)
        await cover.run(10)
        await giveWay()
        #expect(changes.value == 0)
        #expect(panelChanges.value == 10)
        guard case let .workout(after) = cover.store.model else {
            Issue.record("no workout on screen")
            return
        }
        #expect(after.page == before.page)
        #expect(after.header == before.header)
        #expect(cover.store.restPanel?.clock == "2:20")
        // Once the rest is over nothing changes any more.
        await cover.run(140)
        await giveWay()
        changes.setValue(0)
        panelChanges.setValue(0)
        await cover.run(60)
        await giveWay()
        #expect(changes.value == 0)
        #expect(panelChanges.value == 0)
        watching.cancel()
        watchingThePanel.cancel()
        await cover.close()
    }

    @Test("A check and then Minimize at once, the cover's tasks cancelled as it closes: the set is felt, once")
    func logThenMinimize_isFeltOnce() async throws {
        let running = try Fixtures.seedSession()
        let scene = try await WorkoutScene.onHost(live: running)
        let haptics = FakeHaptics()
        let store = scene.store { $0.haptics = haptics }
        let following = Task { await store.follow() }
        let pumping = Task { await store.pump() }
        await eventually("the session's first update") { store.isHearingTheSession }
        store.send(.edit(.log(exerciseIndex: 0, setID: running.exercises[0].sets[0].id)))
        store.send(.minimize)
        await eventually("the cover to close") { store.exit != nil }
        following.cancel()
        pumping.cancel()
        await following.value
        await giveWay()
        #expect(store.exit == .route(.minimized))
        #expect(await haptics.played == [.setLogged])
    }

    @Test("The wall clock set back while a rest runs: the panel follows it, and the rest is felt once, at its end")
    func clockSetBack_whileResting() async throws {
        let (cover, _) = try await Self.resting()
        await cover.run(100.5)
        await cover.back(60)
        #expect(cover.panel?.clock == "1:49")
        #expect(await cover.panelFault() == nil)
        await cover.run(109.5)
        #expect(await cover.panelFault() == nil)
        #expect(cover.panel?.status == "Rest over")
        #expect(await cover.played() == [.setLogged, .restOver])
        await cover.close()
    }

    @Test("A cover that comes up, or tasks that start again, within a second of a rest's end play nothing for it")
    func startedJustAfterTheEnd_playsNothing() async throws {
        // The cover was up at the end: felt once, and not again by what starts half a second later.
        let (cover, _) = try await Self.resting()
        await cover.run(150)
        await cover.suspend(0.5)
        await cover.restartTasks()
        await cover.reopen()
        #expect(await cover.played() == [.setLogged, .restOver])
        #expect(cover.panel?.status == "Rest over")
        await cover.close()
        // The cover was down at the end and comes up half a second after it: the rest had already ended.
        let (minimized, _) = try await Self.resting()
        await minimized.run(149.5)
        await minimized.close()
        minimized.skew.withValue { $0 += 1 }
        await minimized.reopen()
        #expect(minimized.panel?.status == "Rest over")
        #expect(await minimized.played() == [.setLogged])
        await minimized.close()
    }

    @Test("Two waits on the same rest and a haptic that is slow to return: still one buzz")
    func twoWaits_aSlowHaptic_oneBuzz() async throws {
        let running = try Fixtures.seedSession()
        let scene = try WorkoutScene.onFake(live: running)
        let haptics = GatedHaptics()
        let clock = RestProbeClock()
        let store = scene.store {
            $0.haptics = haptics
            $0.continuousClock = clock
            $0.date = DateGenerator { Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1)) }
        }
        let following = Task { await store.follow() }
        await eventually("the session's first update") { store.shown != nil }
        store.send(.edit(.log(exerciseIndex: 0, setID: running.exercises[0].sets[0].id)))
        await store.drain()
        await eventually("the rest on the page") { store.shownRest != nil }
        for _ in 0 ..< 20000 where await haptics.played != [.setLogged] {
            await Task.yield()
        }
        try #require(await haptics.played == [.setLogged], "the logged set was never felt")
        await haptics.hold()
        let waits = [Task { await store.keepRestTime() }, Task { await store.keepRestTime() }]
        await eventually("both waits asleep") { clock.sleeps.value == 2 }
        await clock.base.advance(by: .seconds(150))
        await giveWay()
        #expect(await haptics.played == [.setLogged, .restOver])
        await haptics.release()
        for wait in waits {
            await wait.value
        }
        #expect(await haptics.played == [.setLogged, .restOver])
        following.cancel()
    }

    @Test("Updates that reach the page late, one at a time, behind the answers: each logged set is felt once")
    func laggingUpdates_eachFeltOnce() async throws {
        let bench = try await LaggingRestBench()
        let rows = bench.running.exercises[0].sets
        await bench.session.keepStreamsBehind()
        for edit: WorkoutEdit in [
            .log(exerciseIndex: 0, setID: rows[0].id),
            .log(exerciseIndex: 0, setID: rows[1].id),
            .stepReps(exerciseIndex: 0, setID: rows[2].id, .increment),
            .log(exerciseIndex: 0, setID: rows[2].id),
            .extendRest
        ] {
            bench.store.send(.edit(edit))
        }
        await bench.store.drain()
        #expect(await bench.played() == [], "nothing is felt from a call's answer")
        for _ in 0 ..< 6 {
            await bench.session.deliver(1)
            await giveWay()
        }
        #expect(bench.store.shown?.doneSets == 3)
        #expect(await bench.played() == [.setLogged, .setLogged, .setLogged])
        bench.following.cancel()
    }

    @Test("A workout finished by another hand: the ending update's haptic is felt once, and the cover closes")
    func endingUpdate_isFelt() async throws {
        let (cover, _) = try await Self.resting()
        let ended = try await cover.scene.session.finish(endedAt: cover.now)
        await eventually("the cover to close") { cover.store.exit != nil }
        #expect(cover.store.exit == .route(.saved(ended.id)))
        #expect(await cover.played() == [.setLogged, .workoutFinished])
        await cover.close()
    }

    // MARK: Round 1's findings

    /// F10-S6-1, **as built by ruling 20** ("Plan amendments — slice S6 after round 1": not fixed, pinned
    /// here, recorded for F17 with the other clock cases). Once a rest is over nothing reads the date
    /// until the rest's task runs again. With the wall clock set back under "Rest over", the panel goes on
    /// saying "Rest over" although time is left by the clock; a tap of another kind does not change that
    /// (the panel's moment never goes back for a tap, ruling 18), and nothing is felt at the rest's true
    /// end. "+30s" is judged at the tap's own, earlier, date: it finds the rest still running and extends
    /// it, so the lifter who saw "Rest over" gets what was left plus 30 s, not 30 s. A reopened cover
    /// reads the date and shows the rest running. When F17 rules, this test changes with it.
    @Test(
        "F10-S6-1, as built (ruling 20): the wall clock set back at Rest over leaves Rest over until the rest changes"
    )
    func clockSetBack_atRestOver_thenATap() async throws {
        let (cover, rows) = try await Self.resting()
        await cover.run(150)
        #expect(cover.panel?.status == "Rest over")
        await cover.back(60)
        await cover.tap(.stepReps(exerciseIndex: 0, setID: rows[1].id, .increment))
        #expect(cover.panel?.clock == "0:00", "a tap of another kind leaves the panel as it was")
        #expect(cover.panel?.status == "Rest over")
        await cover.run(10)
        #expect(cover.panel?.status == "Rest over", "ten seconds on, with 50 s left by the clock")
        await cover.run(60)
        #expect(cover.panel?.status == "Rest over", "and past its true end")
        #expect(await cover.played() == [.setLogged, .restOver], "nothing is felt at the true end")
        // The clock set back again, a minute before the rest's end: a reopened cover shows it running.
        await cover.back(70)
        await cover.reopen()
        #expect(cover.panel?.clock == "1:00")
        #expect(await cover.panelFault() == nil)
        await cover.close()
    }

    @Test("F10-S6-1, as built (ruling 20): +30s on that Rest over extends the rest the clock says is running")
    func clockSetBack_atRestOver_thenPlusThirty() async throws {
        let (cover, _) = try await Self.resting()
        await cover.run(150)
        await cover.back(60)
        #expect(cover.panel?.status == "Rest over")
        await cover.tap(.extendRest)
        let rest = await cover.truth()?.shownRest
        #expect(rest?.total == .seconds(180), "the 150 s rest grown, not a rest of 30 s")
        #expect(cover.panel?.clock == "1:30", "what the clock said was left, and 30 s")
        await cover.run(5)
        #expect(cover.panel?.clock == "1:25", "and it counts down again")
        #expect(await cover.panelFault() == nil)
        await cover.close()
    }

    /// F10-S6-2. The rest's task asks the page, not the session, whether its rest is still the shown
    /// one. A "Skip rest" the session has taken and the stream has not yet shown leaves the rest on the
    /// page; if it reaches zero in between, the skipped rest is felt.
    @Test("F10-S6-2: a rest the session has skipped is not felt at zero, though the page has not heard yet")
    func skipped_withThePageBehind_isNotFelt() async throws {
        let bench = try await LaggingRestBench()
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: bench.running.exercises[0].sets[0].id)))
        await bench.store.drain()
        await eventually("the rest on the page") { bench.store.shownRest != nil }
        let keeper = Task { await bench.store.keepRestTime() }
        await giveWay()
        await bench.clock.base.advance(by: .seconds(149))
        await bench.session.keepStreamsBehind()
        bench.store.send(.edit(.skipRest))
        await bench.store.drain()
        #expect(await bench.session.current()?.rest == nil, "the session has skipped it")
        await bench.clock.base.advance(by: .seconds(1))
        await keeper.value
        #expect(await bench.played() == [.setLogged])
        bench.following.cancel()
    }

    /// F10-S6-3. An update's haptics reach only the stream that was open when it was published. A follow
    /// that starts again between a change and its update (criterion 7: "also across the cover's tasks
    /// restarting") begins from the session's workout as it stands, which carries none: the set is on the
    /// page and was never felt.
    @Test("F10-S6-3: a set logged just before the cover's tasks start again is still felt, once")
    func followStartedAgain_withAnUpdateBehind() async throws {
        var bench = try await LaggingRestBench()
        await bench.session.keepStreamsBehind()
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: bench.running.exercises[0].sets[0].id)))
        await bench.store.drain()
        bench.following.cancel()
        await bench.following.value
        await bench.session.keepStreamsBehind(false)
        bench.following = Task { [store = bench.store] in await store.follow() }
        await eventually("the logged set on the page") { bench.store.shown?.doneSets == 1 }
        #expect(await bench.played() == [.setLogged])
        bench.following.cancel()
    }
}
