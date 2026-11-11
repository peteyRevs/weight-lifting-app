@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S3, N19, the store: "Delete all data" waits while a workout is in progress, followed through the session and
/// checked again before the erase begins.
@MainActor
@Suite("SettingsStore · Delete all data and a live workout", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct DeleteAllLiveWorkoutTests {
    @Test("N19. While a workout is in progress the row is off and says why; it comes back when the workout ends")
    func liveWorkout_disablesTheRow() async throws {
        let session = FakeWorkoutSessionClient(live: EventBuilders.seedSession())
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(session: session)
        let task = await scene.running()
        defer { task.cancel() }
        await eventually { scene.store.hasLiveWorkout }
        let row = try scene.model.deleteRow
        #expect(row.action == nil && row.detail == "Finish or discard your workout first")
        scene.store.send(.deleteAll)
        #expect(try scene.model.deleteWarning == nil)
        try await session.discard(endedAt: EventBuilders.start.addingTimeInterval(600))
        await eventually { !scene.store.hasLiveWorkout }
        #expect(try scene.model.deleteRow.action == .deleteAll && scene.model.deleteRow.detail == nil)
        #expect(reset.calls.isEmpty)
    }

    @Test("N19. A workout started while the warning or the sheet is up closes it")
    func workoutStarted_closesTheSheet() async throws {
        let session = FakeWorkoutSessionClient()
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(session: session)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        try await session.start(EventBuilders.seedSession())
        await eventually { scene.store.deleteAll == nil }
        #expect(try scene.model.deleteRow.action == nil)
        scene.store.send(.confirmDeleteAll)
        #expect(reset.calls.isEmpty)
    }

    @Test("N19. A workout the follower has not heard of yet is found before the erase begins: nothing is deleted")
    func workoutFoundAtTheErase_deletesNothing() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(quietLive: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.confirmDeleteAll)
        await eventually { scene.store.deleteAll == nil }
        #expect(scene.store.hasLiveWorkout)
        #expect(reset.calls.isEmpty)
        #expect(try await !scene.memory.workouts.recent(limit: 100).isEmpty)
    }
}
