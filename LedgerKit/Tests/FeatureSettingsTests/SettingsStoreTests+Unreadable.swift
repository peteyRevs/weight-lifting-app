@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S1, the store, continued: unreadable settings (N2), a change made before the run, and the route (N7).
extension SettingsStoreTests {
    @Test("N2. Unreadable settings draw the defaults and save nothing until the lifter changes something")
    func unreadable_drawsTheDefaults_andSavesNothing() async throws {
        var stored = Fixtures.settingsLb
        stored.units = .kg
        let scene = SettingsScene(settings: stored, unreadable: true)
        let task = await scene.running()
        defer { task.cancel() }
        #expect(scene.store.shown == .default)
        #expect(try scene.model.units.options.map(\.isSelected) == [true, false])
        #expect(scene.watched.saves.isEmpty)
    }

    @Test("N2. The first change saves the whole value over the unreadable row, and the store follows it again")
    func unreadable_firstChangeSavesWhole_thenFollowsAgain() async throws {
        let scene = SettingsScene(unreadable: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setDefaultRest(RestDuration(clampingSeconds: 60)))
        await eventually { scene.store.pending == nil && scene.store.isUnreadable == false }
        var saved = Settings.default
        saved.defaultRest = RestDuration(clampingSeconds: 60)
        #expect(scene.watched.saves == [saved])
        // Followed again: a save made elsewhere reaches the screen.
        var elsewhere = saved
        elsewhere.weekStart = .saturday
        try await scene.memory.settings.save(elsewhere)
        await eventually { scene.store.model?.weekStart.value == "Saturday" }
    }

    @Test("A change made before the run starts is saved when it does")
    func changeBeforeTheRun_isSavedByIt() async throws {
        let scene = SettingsScene()
        let first = await scene.running()
        first.cancel()
        await first.value
        scene.store.send(.setUnits(.kg))
        let second = Task { await scene.store.run() }
        defer { second.cancel() }
        await eventually { scene.store.pending == nil }
        #expect(try await scene.stored().units == .kg)
    }

    @Test("N7. Diagnostics hands the app one route, however often it is tapped")
    func diagnostics_routeHandedOnce() async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        let action = try #require(scene.model.diagnostics).action
        scene.store.send(action)
        scene.store.send(action)
        var handed: [SettingsRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.debugMenu])
        #expect(scene.watched.saves.isEmpty)
    }
}
