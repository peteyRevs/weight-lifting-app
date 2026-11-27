import Foundation
import LedgerDomain
import LedgerSnapshotTesting
import LedgerTestSupport
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S5a: the root shows the screen of the store's mode (criterion 1's idle, the summary's stub), "Start" on
/// the screen before a workout sends the store's start, and the no-program line names the app it was handed
/// (criterion 16). A watch test cannot host a view or tap it, so the root's screen is read from the store
/// (`WatchWorkoutRoot.screen(of:)`) and drawn, and a tap is the action the screen hands its pill.
@MainActor
@Suite("WatchWorkoutRoot", .tags(.watch), .timeLimit(.minutes(1)))
struct WatchWorkoutRootTests {
    typealias Scene = WatchStoreScene

    /// The root's screen by name, so that a test compares a word, never a model.
    static func shown(_ store: WatchWorkoutStore) -> String {
        switch WatchWorkoutRoot.screen(of: store) {
        case .waiting: "waiting"
        case .idle: "idle"
        case .ready: "ready"
        case .rest: "rest"
        case .summary: "summary"
        }
    }

    /// Draws the root over `store` as it stands, and says whether it drew.
    static func draws(_ store: WatchWorkoutStore) -> Bool {
        renderPreview(size: WatchSize.mm46.size) { WatchWorkoutRoot(store: store) }
    }

    @Test("The root follows the mode: idle, set ready, rest, set ready, summary, and idle again after Done")
    func root_followsTheMode() async throws {
        let scene = try Scene()
        let (store, task) = await scene.running()
        #expect(Self.shown(store) == "idle" && Self.draws(store))
        store.send(.start)
        await observed("set ready") { Self.shown(store) == "ready" }
        #expect(Self.draws(store))
        store.send(.logSet)
        await observed("a set logged") { store.workout?.doneSets == 1 }
        await Scene.settled(store)
        try await scene.fake?.apply(.restStarted(endsAt: Fixtures.now.addingTimeInterval(60), total: .seconds(60)))
        await observed("rest") { Self.shown(store) == "rest" }
        #expect(Self.draws(store))
        store.send(.skipRest)
        await observed("set ready again") { Self.shown(store) == "ready" }
        store.send(.openEnd)
        store.send(.save)
        await observed("summary") { Self.shown(store) == "summary" }
        #expect(Self.draws(store))
        let summary = try #require(store.summary)
        WatchStubScreen(lines: [summary.title], pill: (summary.done, .dismissSummary), send: store.send).tap()
        #expect(Self.shown(store) == "idle" && WatchWorkoutRootTests.plan(store)?.start == nil, "the day is logged")
        task.cancel()
    }

    @Test("Before the store has heard its sources the root draws the black ground alone")
    func root_waitsForItsSources() {
        let store = withTestDependencies { WatchWorkoutStore(appName: "Ledger") }
        #expect(Self.shown(store) == "waiting" && Self.draws(store))
        let root = withTestDependencies { WatchWorkoutRoot(appName: "Ledger", health: nil) }
        #expect(renderPreview(size: WatchSize.mm46.size) { root })
    }

    @Test("Start on the screen sends the store's start, which reaches set ready; a screen without Start has none")
    func start_sendsTheIntent() async throws {
        var sent: [WatchAction] = []
        let plan = try #require(IdleSample.plan.model)
        WatchIdleScreen(model: plan, send: { sent.append($0) }).start?()
        #expect(sent == [.start])
        for sample in [IdleSample.restDay, .noProgram, .logged] {
            let model = try #require(sample.model)
            #expect(WatchIdleScreen(model: model, send: { _ in }).start == nil, "\(sample)")
        }
        let restDay = try WatchIdleContent(#require(IdleSample.restDay.model))
        #expect(restDay.pill == .init(title: "Next: Friday · UB", isStart: false) && restDay.title == "Rest day")

        let scene = try Scene()
        let (store, task) = await scene.running()
        let idle = try #require(store.idle)
        #expect(WatchIdleContent(idle).pill == .init(title: "Start", isStart: true))
        WatchIdleScreen(model: idle, send: store.send).start?()
        await observed("set ready") { store.mode == .ready }
        task.cancel()
    }

    @Test("No program on the watch: the title, and the outlined line names the app the root was handed")
    func noProgram_namesTheApp() async throws {
        let seed = try InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), settings: Fixtures.settingsLb)
        let scene = try Scene(seed: seed, appName: "Lift Log")
        let (store, task) = await scene.running()
        let model = try #require(store.idle)
        let content = WatchIdleContent(model)
        #expect(content.title == "No program on watch" && content.eyebrow == nil && content.line == nil)
        #expect(content.pill == .init(title: "Open Lift Log on iPhone", isStart: false))
        #expect(WatchIdleScreen(model: model, send: { _ in }).start == nil, "the line does nothing")
        task.cancel()
    }

    static func plan(_ store: WatchWorkoutStore) -> WatchIdleModel.Plan? {
        if case let .plan(plan)? = store.idle {
            plan
        } else {
            nil
        }
    }
}
