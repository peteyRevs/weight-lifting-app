import Foundation
import LedgerDomain
import LedgerSnapshotTesting
import LedgerTestSupport
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S5b: set ready and the rest screen. The root shows each in its mode, "GO" included; each control sends its
/// intent; the Health line asks once; the ring reads its time; and the rest-over shake keeps still under Reduce
/// Motion. A watch test cannot host a view or tap it, so a tap is the screen's own action, which its control calls.
@MainActor
@Suite("Watch set ready and rest screens", .tags(.watch), .timeLimit(.minutes(1)))
struct WatchLiveScreenTests {
    typealias Scene = WatchStoreScene

    static func draws(_ store: WatchWorkoutStore) -> Bool {
        WatchWorkoutRootTests.draws(store)
    }

    @Test("The root shows set ready, the rest, GO on the rest screen at zero, then set ready again")
    func root_routesReadyRestAndGo() async throws {
        let rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(60), total: .seconds(60))
        let scene = try Scene(live: Scene.lowerA([(0, 0)]))
        try await scene.buzz(false)
        let (store, task) = await scene.running(timed: true)
        #expect(WatchWorkoutRootTests.shown(store) == "ready" && Self.draws(store))
        try await scene.fake?.apply(.restStarted(endsAt: rest.endsAt, total: rest.total))
        await observed("the rest") { WatchWorkoutRootTests.shown(store) == "rest" }
        #expect(store.rest?.isOver == false && store.rest?.title == "REST" && Self.draws(store))
        await scene.clockWait("the rest's task asleep") { scene.clock.asleep == 1 }
        scene.clock.advance(by: .seconds(60))
        await observed("GO") { store.rest?.isOver == true }
        #expect(WatchWorkoutRootTests.shown(store) == "rest" && store.rest?.title == "GO" && Self.draws(store))
        await scene.clockWait("GO's wait") { scene.clock.asleep == 1 }
        scene.clock.advance(by: WatchMode.goWindow)
        await observed("set ready after GO") { WatchWorkoutRootTests.shown(store) == "ready" }
        task.cancel()
    }

    @Test("Set ready's controls: Done set logs, the name opens the list, − and + step the reps, the crown turns")
    func ready_controlsSendTheirIntents() throws {
        var sent: [WatchAction] = []
        let model = try #require(LiveSample.ready.readyModel)
        let screen = WatchReadyScreen(model: model, dial: LiveSample.ready.dial, send: { sent.append($0) })
        screen.logSet()
        screen.openList()
        screen.decreaseReps()
        screen.increaseReps()
        screen.rotate(190)
        screen.restCrown()
        #expect(sent == [
            .logSet,
            .openList,
            .stepReps(.downward),
            .stepReps(.upward),
            .crownRotated(190),
            .crownRested
        ])
        #expect(screen.canDecreaseReps, "five reps")
        #expect(WatchWorkoutCopy.decreaseReps == "Decrease reps" && WatchWorkoutCopy.increaseReps == "Increase reps")
        #expect(WatchWorkoutCopy.doneSet == "Done set")
    }

    @Test("Done set on the screen logs the shown set; at one rep − is disabled and sends nothing (min 1)")
    func ready_doneSetLogs_repsMinimumOne() async throws {
        var live = try Scene.lowerA()
        live.exercises[0].sets[0].reps = .one
        let scene = try Scene(live: live)
        let (store, task) = await scene.running()
        let screen = try WatchReadyScreen(model: #require(store.ready), dial: store.crownDial, send: store.send)
        #expect(!screen.canDecreaseReps && store.ready?.reps == "× 1")
        screen.decreaseReps()
        await Scene.settled(store)
        #expect(await scene.fake?.applied.isEmpty == true, "− at one rep sends nothing")
        screen.logSet()
        await observed("the set logged") { store.workout?.exercises[0].sets[0].isDone == true }
        task.cancel()
    }

    @Test("The rest's controls: +30s extends the rest by 30 s, Skip ends it")
    func rest_extendAndSkip() async throws {
        var sent: [WatchAction] = []
        let model = try #require(LiveSample.rest.restModel)
        WatchRestScreen(model: model, send: { sent.append($0) }).extend()
        WatchRestScreen(model: model, send: { sent.append($0) }).skip()
        #expect(sent == [.extendRest, .skipRest])
        #expect(WatchWorkoutCopy.extendRest == "+30s" && WatchWorkoutCopy.extendRestLabel == "Add 30 seconds")

        let scene = try Scene(live: Scene.lowerA([(0, 0)]))
        let (store, task) = await scene.running()
        let ends = Fixtures.now.addingTimeInterval(60)
        try await scene.fake?.apply(.restStarted(endsAt: ends, total: .seconds(60)))
        await observed("the rest") { store.rest != nil }
        let screen = try WatchRestScreen(model: #require(store.rest), send: store.send)
        screen.extend()
        await observed("30 s more") { store.rest?.endsAt == ends.addingTimeInterval(30) }
        #expect(store.rest?.timer.total == .seconds(90))
        screen.skip()
        await observed("set ready") { store.mode == .ready }
        task.cancel()
    }

    @Test("Health denied: the line asks once, until the first set logged, and not again")
    func denied_lineShowsOnce() async throws {
        let scene = try Scene(live: Scene.lowerA(), health: FakeHealthStore(authorization: .denied))
        let (store, task) = await scene.running()
        await observed("denied") { store.health == .denied }
        #expect(store.ready?.healthLine == "Allow Health in iPhone Settings" && !store.hasAskedForHealth)
        store.send(.logSet)
        await observed("the set logged") { store.workout?.doneSets == 1 }
        #expect(store.hasAskedForHealth && store.ready?.healthLine == nil && store.ready?.heartRate.value == "—")
        store.send(.skipRest)
        store.send(.logSet)
        await observed("the second set logged") { store.workout?.doneSets == 2 }
        #expect(store.ready?.healthLine == nil, "once")
        task.cancel()
    }

    @Test("Health allowed: Done set does not use up the one-time line")
    func allowed_keepsTheLineUnasked() async throws {
        let scene = try Scene(live: Scene.lowerA())
        let (store, task) = await scene.running()
        store.send(.logSet)
        await observed("the set logged") { store.workout?.doneSets == 1 }
        #expect(!store.hasAskedForHealth)
        task.cancel()
    }

    @Test("Reduce Motion: no shake at GO; otherwise three shakes on the prototype's keyframes, still at their ends")
    func reduceMotion_disablesTheShake() {
        #expect(WatchRestScreen.shakes(atRestOver: true, reduceMotion: false))
        #expect(!WatchRestScreen.shakes(atRestOver: true, reduceMotion: true), "criterion 15")
        #expect(!WatchRestScreen.shakes(atRestOver: false, reduceMotion: false))
        let thousandths = { (value: CGFloat) in (value * 1000).rounded() / 1000 }
        let offsets = [0, 0.1, 0.2, 0.4, 0.6, 0.8, 1, 2.2, 3].map { thousandths(WatchBuzzShake.offset(at: $0)) }
        #expect(offsets == [0, -1, -2, 2, -1.333, 1.333, 0, -2, 0])
        #expect(WatchBuzzShake.offset(at: .infinity) == 0 && WatchBuzzShake.duration == 0.38 * 3)
        var shake = WatchBuzzShake(cycles: 0)
        shake.animatableData = 0.2
        #expect(shake.cycles == 0.2 && shake.effectValue(size: .zero).m31 == -2)
    }

    @Test("The ring reads Rest, 42 seconds remaining, then Rest over; time can stand still for a snapshot")
    func ring_readsItsTime() throws {
        let model = try #require(LiveSample.rest.restModel)
        #expect(model.ringSummary(at: model.endsAt.addingTimeInterval(-42)) == "Rest, 42 seconds remaining")
        #expect(model.ringSummary(at: model.endsAt.addingTimeInterval(-74.5)) == "Rest, 1 minute, 15 seconds remaining")
        #expect(model.ringSummary(at: model.endsAt) == "Rest over")
        #expect(WatchTimeline.fixed(at: Fixtures.now).moment(.distantPast) == Fixtures.now)
        #expect(WatchTimeline.live.moment(.distantPast) == .distantPast)
        let never = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(WatchTimeline.live.timer(from: never, countsDown: false, fallback: "0:00") == Text(verbatim: "0:00"))
    }
}
