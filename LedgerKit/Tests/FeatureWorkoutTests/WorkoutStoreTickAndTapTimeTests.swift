import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// F10 S6 after round 1. Criterion 16: a tick of a rest changes the rest panel and nothing else the cover
/// observes. Criterion 18: the time of a tap is the time it was tapped, however long the taps before it
/// take to save.
@MainActor
@Suite("WorkoutStore · a tick's reach, and a tap's time", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreTickAndTapTimeTests {
    typealias Bench = RestBench
    typealias Pump = WorkoutStorePumpTests

    // MARK: Criterion 16

    @Test("A second of a rest fires for a reader of restPanel and not for a reader of model")
    func tick_firesForThePanelOnly() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        let model = LockIsolated(0)
        let panel = LockIsolated(0)
        withObservationTracking { _ = bench.store.model } onChange: { model.withValue { $0 += 1 } }
        withObservationTracking { _ = bench.store.restPanel } onChange: { panel.withValue { $0 += 1 } }
        let before = bench.store.model
        await bench.second(keeper)
        #expect(model.value == 0, "the root, the header and the page read `model`: a tick must not reach them")
        #expect(panel.value == 1)
        let isSameModel = bench.store.model == before
        #expect(isSameModel)
        #expect(bench.panel?.clock == ClockText.remaining(.seconds(bench.rest - 1)))
        keeper.task.cancel()
        bench.following.cancel()
    }

    @Test("The check is real: a change of the workout fires for a reader of model")
    func change_firesForTheModel() async throws {
        let bench = try await Bench()
        let model = LockIsolated(0)
        withObservationTracking { _ = bench.store.model } onChange: { model.withValue { $0 += 1 } }
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        #expect(model.value == 1)
        bench.following.cancel()
    }

    @Test("The screen's model holds no time: it is the same value at two moments of a rest")
    func model_holdsNoMoment() {
        let state = WorkoutRestPlanTests.resting(secondsLeft: 75)
        let screen = WorkoutPresentation.screen(
            .loaded(state), isBusy: false, locale: Fixtures.locale, calendar: Fixtures.calendar
        )
        guard case let .workout(model) = screen else {
            Issue.record("no workout on screen")
            return
        }
        // Its two parts are the header and the page; the panel is the store's (`restPanel`).
        #expect(Mirror(reflecting: model).children.compactMap(\.label) == ["header", "page"])
    }

    // MARK: Criterion 18

    /// A cover's store over the real host, whose date the test moves.
    @MainActor
    struct Held {
        let scene: WorkoutScene
        let store: WorkoutStore
        let date = LockIsolated(Fixtures.now)
        let following: Task<Void, Never>

        init(_ running: WorkoutState) async throws {
            scene = try await WorkoutScene.onHost(live: running)
            store = scene.store { [date] in $0.date = DateGenerator { date.value } }
            following = Task { [store] in await store.follow() }
            await eventually { [store] in store.shown != nil }
        }
    }

    @Test("+30s tapped with 2 s left, applied 5 s later behind a held save, extends the rest it was tapped on")
    func extend_behindAHeldSave_carriesTheTapsTime() async throws {
        let running = try Fixtures.seedSession()
        let rows = Pump.sets(0, of: running)
        let held = try await Held(running)
        let (scene, store, date, following) = (held.scene, held.store, held.date, held.following)
        store.send(.edit(.log(exerciseIndex: 0, setID: rows[0])))
        await store.drain()
        let rest = try #require(try await Pump.live(scene).rest)
        #expect(rest == RestTimer(endsAt: Fixtures.now.addingTimeInterval(150), total: .seconds(150)))

        // 148 s on: a stepper whose save is held, and "+30s" tapped behind it with 2 s of the rest left.
        date.setValue(Fixtures.now.addingTimeInterval(148))
        await scene.probe.hold(.append)
        store.send(.edit(.stepReps(exerciseIndex: 0, setID: rows[1], .increment)))
        let draining = Task { await store.drain() }
        try await scene.probe.waitUntilHeld()
        store.send(.edit(.extendRest))
        // The save takes 5 s: the rest's first end has passed when "+30s" has its turn.
        date.setValue(Fixtures.now.addingTimeInterval(153))
        await scene.probe.release()
        await draining.value

        let after = try #require(try await Pump.live(scene).rest)
        #expect(after == RestTimer(endsAt: Fixtures.now.addingTimeInterval(180), total: .seconds(180)))
        following.cancel()
    }

    @Test("A set logged behind a held save is done at the moment its check was tapped")
    func log_behindAHeldSave_carriesTheTapsTime() async throws {
        let running = try Fixtures.seedSession()
        let rows = Pump.sets(0, of: running)
        let held = try await Held(running)
        let (scene, store, date, following) = (held.scene, held.store, held.date, held.following)
        await scene.probe.hold(.append)
        store.send(.edit(.stepReps(exerciseIndex: 0, setID: rows[1], .increment)))
        let draining = Task { await store.drain() }
        try await scene.probe.waitUntilHeld()
        date.setValue(Fixtures.now.addingTimeInterval(10))
        store.send(.edit(.log(exerciseIndex: 0, setID: rows[0])))
        date.setValue(Fixtures.now.addingTimeInterval(15))
        await scene.probe.release()
        await draining.value

        let after = try await Pump.live(scene)
        #expect(after.exercises[0].sets[0].doneAt == Fixtures.now.addingTimeInterval(10))
        #expect(after.rest?.endsAt == Fixtures.now.addingTimeInterval(160))
        following.cancel()
    }

    @Test("A tap that waited is older than the rest's last tick: the panel's moment does not go back for it")
    func momentNeverGoesBackForATap() async throws {
        let bench = try await Bench()
        try await bench.tap(.log(exerciseIndex: 0, setID: bench.first))
        let keeper = await bench.keepingTime()
        // Tapped now, and applied only after three more seconds of the rest have been read.
        bench.store.send(.edit(.stepReps(exerciseIndex: 0, setID: bench.running.exercises[0].sets[1].id, .increment)))
        await bench.seconds(3, keeper)
        await bench.store.drain()
        #expect(bench.store.moment == Fixtures.now.addingTimeInterval(3))
        keeper.task.cancel()
        bench.following.cancel()
    }
}
