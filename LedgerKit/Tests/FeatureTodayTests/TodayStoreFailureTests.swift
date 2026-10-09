@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5, criterion 6: a read that fails is shown, and a later good one recovers it.
@MainActor
@Suite("TodayStore: a read that fails", .tags(.feature), .timeLimit(.minutes(1)))
struct TodayStoreFailureTests {
    typealias Scene = TodayScene

    @Test("6. A read that fails shows the failure, and the next change that reads well recovers it")
    func readFails_showsFailed_thenRecovers() async throws {
        let scene = try Scene()
        scene.workouts.isFailing = true
        let task = await scene.running()
        #expect(scene.store.phase == "failed")
        scene.workouts.isFailing = false
        var settings = Fixtures.settingsLb
        settings.weekStart = .sunday
        try await scene.stores.settings.save(settings)
        await eventually { scene.store.model != nil }
        #expect(scene.store.model?.card.upNext?.title == "Lower A — Squat focus")

        // A read that fails over a loaded model is shown too, and a new run recovers it.
        scene.workouts.isFailing = true
        try await scene.stores.settings.save(Fixtures.settingsLb)
        await eventually { scene.store.isFailed }
        scene.workouts.isFailing = false
        task.cancel()
        await task.value
        let next = Task { await scene.store.run() }
        await eventually { scene.store.model != nil }
        next.cancel()
    }

    @Test("6. A store's observation that ends before a value shows the failure, not a blank screen")
    func streamEndsBeforeAValue_showsFailed() async throws {
        let scene = try Scene { $0.programRepository = EndedPrograms() }
        let task = await scene.running()
        guard case let .failed(error) = scene.store.state else {
            Issue.record("the store shows \(scene.store.phase)")
            return
        }
        #expect(error as? TodayStoreError == .observationEnded)
        task.cancel()
    }

    @Test("6. A read that ends after the root went away shows nothing, failed or not", arguments: [true, false])
    func cancelledWhileReading_showsNothing(fails: Bool) async throws {
        let scene = try Scene()
        let gate = scene.workouts.hold()
        let task = Task { await scene.store.run() }
        await gate.waitForArrival()
        task.cancel()
        scene.workouts.isFailing = fails
        gate.open()
        await task.value
        #expect(scene.store.phase == "loading")
    }
}
