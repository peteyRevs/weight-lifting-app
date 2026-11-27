import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import SwiftUI
import Testing
@testable import WatchFeatureWorkout

/// F18 S6a: the session list, the summary and the takeover banner. The root shows the list in the live screen's
/// place and closes it on a change of mode; each control sends its intent; NEW PR is orange only with a record; and
/// the banner shows while another app's workout holds Health. A watch test cannot host a view or tap it, so a tap is
/// the screen's own action, which its control calls.
@MainActor
@Suite("Watch list, summary and banner screens", .tags(.watch), .timeLimit(.minutes(1)))
struct WatchOverlayScreenTests {
    typealias Scene = WatchStoreScene

    static func shown(_ store: WatchWorkoutStore) -> String {
        WatchWorkoutRootTests.shown(store)
    }

    @Test("The list's controls: ‹ closes it, a row selects its exercise, End workout opens the end overlay")
    func list_controlsSendTheirIntents() throws {
        var sent: [WatchAction] = []
        let model = try #require(OverlaySample.listModel)
        let list = WatchListOverlay(model: model, send: { sent.append($0) })
        list.close()
        list.select(2)
        list.openEnd()
        #expect(sent == [.closeList, .selectExercise(2), .openEnd])
        #expect(model.header == "1 OF 4 DONE" && model.rows[0].isDone && model.rows[1].isCurrent)
        #expect(WatchWorkoutCopy.closeList == "Back" && WatchWorkoutCopy.allSetsLogged == "All sets logged")
    }

    @Test("The root shows the list once the name is tapped; a row selects its exercise and the list closes")
    func root_listSelects() async throws {
        let scene = try Scene(live: Scene.lowerA())
        let (store, task) = await scene.running()
        try WatchReadyScreen(model: #require(store.ready), dial: store.crownDial, send: store.send).openList()
        #expect(Self.shown(store) == "list" && WatchWorkoutRootTests.draws(store))
        let model = try #require(store.list)
        WatchListOverlay(model: model, send: store.send).select(2)
        #expect(Self.shown(store) == "ready", "the list closed")
        await observed("the third exercise") { store.list?.rows[2].isCurrent == true }
        #expect(await scene.fake?.applied.count == 1)
        WatchListOverlay(model: model, send: store.send).close()
        #expect(Self.shown(store) == "ready")
        task.cancel()
    }

    @Test("A change of mode while the list is open closes it: the rest shows in its place")
    func root_listClosesOnModeChange() async throws {
        let scene = try Scene(live: Scene.lowerA())
        let (store, task) = await scene.running()
        store.send(.openList)
        #expect(Self.shown(store) == "list")
        try await scene.fake?.apply(.restStarted(endsAt: Fixtures.now.addingTimeInterval(90), total: .seconds(90)))
        await observed("the rest") { Self.shown(store) == "rest" }
        #expect(store.shownOverlay == nil && WatchWorkoutRootTests.draws(store))
        task.cancel()
    }

    @Test("NEW PR is orange with a record, dimmed with the wrist down, and 55 % white without; Done dismisses")
    func summary_recordsColourAndDone() throws {
        #expect(WatchSummaryScreen.recordsColor(hasRecords: true, isLuminanceReduced: false) == LedgerColor.accent)
        #expect(WatchSummaryScreen.recordsColor(hasRecords: true, isLuminanceReduced: true) == WatchTokens.accentDimmed)
        #expect(WatchSummaryScreen.recordsColor(hasRecords: false, isLuminanceReduced: false)
            == LedgerColor.watchInkSecondary)
        let records = try #require(SummarySample.records.model)
        let none = try #require(SummarySample.noRecords.model)
        #expect(records.hasRecords && records.records == "2" && records.averageHeartRate == "138")
        #expect(!none.hasRecords && none.records == "0" && none.averageHeartRate == "—")
        #expect(records.elapsed == "55:00" && records.sets == "15/15")
        var sent: [WatchAction] = []
        WatchSummaryScreen(model: records, send: { sent.append($0) }).done()
        #expect(sent == [.dismissSummary])
    }

    @Test("Apple Workout takes over: the banner shows over the live screen, and not once the workout is saved")
    func banner_showsOnTakeover() async throws {
        let health = FakeHealthStore(authorization: .authorized)
        let scene = try Scene(health: health)
        let (store, task) = await scene.running()
        store.send(.start)
        await observed("the session") { store.mode == .ready && store.healthState.running != nil }
        #expect(store.banner == nil)
        await health.simulateAnotherWorkoutSessionStarted()
        await observed("the banner") { store.banner != nil }
        #expect(store.banner == "Apple Workout took over · logging continues" && WatchWorkoutRootTests.draws(store))
        store.send(.logSet)
        await observed("a set logged") { store.workout?.doneSets == 1 }
        store.send(.openEnd)
        store.send(.save)
        await observed("the summary") { store.mode == .summary }
        #expect(store.banner == nil && WatchWorkoutRootTests.draws(store))
        task.cancel()
    }
}
