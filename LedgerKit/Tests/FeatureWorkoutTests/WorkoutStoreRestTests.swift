import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S6, criteria 1 and 4 to 7: the rest through the store. "+30s" and "Skip rest" go through the pump,
/// as every tap of the page does; the haptics an update carries are played by `follow()`, each once. The
/// rest's time and `.restOver` are `WorkoutStoreRestTimeTests`'. The bench is `RestBench`.
@MainActor
@Suite("WorkoutStore · rest", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreRestTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Bench = RestBench

    // MARK: Criteria 1 and 5: the panel, and its two buttons through the pump

    @Test("Logging a set shows the panel at the rest's start, and the store sent the one event")
    func log_showsThePanel() async throws {
        let bench = try await Bench()
        #expect(bench.panel == nil)
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        #expect(await bench.scene.fake?.applied.count == 1, "the store sends no rest event of its own")
        let panel = try #require(bench.panel)
        #expect(panel.clock == ClockText.remaining(.seconds(bench.rest)))
        #expect(panel.fraction == 1)
        #expect(panel.status == "Resting")
        bench.following.cancel()
    }

    @Test("With auto rest off, logging shows no panel")
    func autoRestOff_noPanel() async throws {
        var off = try Fixtures.seedSession()
        off.autoRest = false
        let bench = try await Bench(off)
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        #expect(bench.store.shown?.exercises[0].sets[0].isDone == true)
        #expect(bench.panel == nil)
        #expect(bench.store.shownRest == nil)
        bench.following.cancel()
    }

    @Test("+30s while resting extends the shown rest, read at the tap's date; the ring rescales")
    func extend_whileResting() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        bench.date.withValue { $0 += 60 }
        try await bench.tap(.extendRest)
        #expect(await bench.scene.fake?.applied.last == .restExtended(
            amount: .seconds(30), extendsShownRest: true, tappedAt: Fixtures.now.addingTimeInterval(60)
        ))
        let rest = try #require(bench.store.shownRest)
        #expect(rest.total == .seconds(bench.rest + 30))
        #expect(rest.endsAt == Fixtures.now.addingTimeInterval(bench.rest + 30))
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest - 30)))
        bench.following.cancel()
    }

    @Test("+30s at Rest over starts a rest of 30 s at the tap; Skip rest takes the panel away")
    func extend_atRestOver_thenSkip() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        bench.date.withValue { $0 += 1000 }
        try await bench.tap(.extendRest)
        let tapped = Fixtures.now.addingTimeInterval(1000)
        #expect(await bench.scene.fake?.applied.last == .restExtended(
            amount: .seconds(30), extendsShownRest: false, tappedAt: tapped
        ))
        #expect(bench.store.shownRest == RestTimer(endsAt: tapped.addingTimeInterval(30), total: .seconds(30)))
        #expect(bench.panel?.clock == "0:30")
        #expect(bench.panel?.status == "Resting")

        try await bench.tap(.skipRest)
        #expect(await bench.scene.fake?.applied.last == .restSkipped)
        #expect(bench.panel == nil)
        bench.following.cancel()
    }

    @Test("Quick taps are applied in order, each once: two +30s are a minute; a double Skip skips once")
    func quickTaps_inOrder_eachOnce() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        try await bench.tap(.extendRest, .extendRest)
        #expect(bench.store.shownRest?.total == .seconds(bench.rest + 60))
        try await bench.tap(.skipRest, .skipRest, .extendRest)
        let applied = await bench.scene.fake?.applied ?? []
        #expect(applied.count == 4, "the second skip and the +30s behind it found no rest shown")
        #expect(applied.last == .restSkipped)
        #expect(bench.panel == nil)
        bench.following.cancel()
    }

    @Test("The next logged set replaces Rest over with its own rest; un-logging a set keeps the rest (rule 22)")
    func nextSet_replaces_unlogKeeps() async throws {
        let bench = try await Bench()
        let second = bench.running.exercises[0].sets[1].id
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        bench.date.withValue { $0 += 1000 }
        try await bench.tap(.log(exerciseIndex: 0, setID: second))
        let rest = try #require(bench.store.shownRest)
        #expect(rest.endsAt == Fixtures.now.addingTimeInterval(1000 + bench.rest))
        bench.date.withValue { $0 += 10 }
        try await bench.tap(.unlog(exerciseIndex: 0, setID: second))
        #expect(bench.store.shown?.exercises[0].sets[1].isDone == false)
        #expect(bench.store.shownRest == rest)
        #expect(bench.panel?.status == "Resting")
        bench.following.cancel()
    }

    @Test("A refused rest change is shown as any refused change, and drops the taps behind it")
    func refused_dropsTheLaterTaps() async throws {
        let running = try Fixtures.seedSession()
        let scene = try await WorkoutScene.onHost(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[0])))
        await store.drain()
        await eventually { store.shownRest != nil }
        await scene.probe.clearCalls()
        await scene.probe.fail(.append)
        store.send(.edit(.skipRest))
        store.send(.edit(.extendRest))
        await store.drain()
        #expect(store.dialog == .editFailed)
        #expect(await scene.appends() == 1)
        #expect(store.shownRest != nil, "the page stays as the session last said")
        task.cancel()
    }

    @Test("Minimize waits for a rest tap made before it")
    func minimize_waits() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        bench.store.send(.edit(.skipRest))
        bench.store.send(.minimize)
        #expect(bench.store.exit == nil)
        await bench.store.drain()
        #expect(bench.store.exit == .route(.minimized))
        #expect(await bench.scene.fake?.applied.last == .restSkipped)
        bench.following.cancel()
    }
}

/// F10 S6, criterion 7: exactly one subscriber, the store's `follow()`, plays each update's haptics, each
/// once, also across the cover's tasks starting again.
@MainActor
@Suite("WorkoutStore · haptics", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreHapticsTests {
    typealias Bench = RestBench

    @Test("A logged set is felt once; a stepper, a skip and an un-log are not felt")
    func haptics_playedOnce() async throws {
        let bench = try await Bench()
        try await bench.tap(.stepWeight(exerciseIndex: 0, setID: bench.first, .increment))
        #expect(await bench.haptics.played == [])
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        await eventuallyPlayed(bench.haptics, [.setLogged])
        bench.date.withValue { $0 += 5 }
        try await bench.tap(.skipRest, .unlog(exerciseIndex: 0, setID: bench.first))
        #expect(await bench.haptics.played == [.setLogged])
        bench.following.cancel()
    }

    @Test("The cover's tasks starting again play nothing a second time, and a second cover plays nothing old")
    func haptics_notAgainAfterARestart() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        await eventuallyPlayed(bench.haptics, [.setLogged])
        bench.following.cancel()
        await bench.following.value
        let again = Task { [store = bench.store] in await store.follow() }
        while !bench.store.isHearingTheSession {
            await Task.yield()
        }
        let second = bench.running.exercises[0].sets[1].id
        try await bench.tap(.log(exerciseIndex: 0, setID: second))
        await eventuallyPlayed(bench.haptics, [.setLogged, .setLogged])
        // Another cover over the same session: the stream's first update carries no haptic.
        let other = FakeHaptics()
        let reopened = bench.scene.store { $0.haptics = other }
        let reopenedTask = Task { await reopened.follow() }
        await eventually { reopened.shown != nil }
        #expect(await other.played == [])
        again.cancel()
        reopenedTask.cancel()
    }

    @Test("Only the store plays: a change made by another hand is felt once, through the stream")
    func haptics_ofAChangeElsewhere() async throws {
        let bench = try await Bench()
        let row = bench.running.exercises[0].sets[0]
        try await bench.scene.session.apply(.setLogged(
            exerciseIndex: 0, setID: row.id, weight: row.weight, reps: row.reps, doneAt: Fixtures.now
        ))
        await eventuallyPlayed(bench.haptics, [.setLogged])
        bench.following.cancel()
    }
}
