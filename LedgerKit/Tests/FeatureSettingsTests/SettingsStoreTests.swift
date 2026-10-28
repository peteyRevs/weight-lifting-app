@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S1, the store: each preference round-trips through the repository (criteria 1, 2, 7, 8), one save of the
/// whole settings per change (N1), serial saves folded while one runs (N1, R7), a failure that reverts (N1),
/// unreadable settings (N2), and a route handed once (N7).
@MainActor
@Suite("SettingsStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct SettingsStoreTests {
    @Test("The first model draws the stored settings")
    func run_firstModel_drawsTheStoredSettings() async throws {
        var stored = Fixtures.settingsLb
        stored.units = .kg
        stored.weekStart = .thursday
        let scene = SettingsScene(settings: stored)
        let task = await scene.running()
        defer { task.cancel() }
        let model = try scene.model
        #expect(model.units.options.map(\.isSelected) == [false, true])
        #expect(model.weekStart.value == "Thursday")
        #expect(scene.watched.saves.isEmpty, "reading saves nothing")
    }

    @Test(
        "Criteria 1, 2, 7, 8. Each preference is saved once, whole, and the screen shows it at once",
        arguments: [
            SettingsAction.setUnits(.kg), .setDefaultRest(RestDuration(clampingSeconds: 105)),
            .setWeekStart(.saturday), .setPlateMath(false), .setAutoRest(false), .setWatchBuzz(false)
        ]
    )
    func change_savedOnceWhole_andShownAtOnce(_ action: SettingsAction) async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        let before = try scene.model
        scene.store.send(action)
        let shown = try scene.model
        #expect(shown != before, "the control shows the lifter's value before the save returns")
        await eventually { scene.store.pending == nil }
        let stored = try await scene.stored()
        #expect(scene.watched.saves == [stored])
        #expect(stored != Fixtures.settingsLb)
        #expect(try scene.model == shown)
    }

    @Test("Criterion 1. KG saves units = kg and nothing else; a second tap on KG saves nothing")
    func kilograms_savesTheUnitsAlone() async {
        let scene = SettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.pending == nil }
        scene.store.send(.setUnits(.kg))
        var expected = Fixtures.settingsLb
        expected.units = .kg
        #expect(scene.watched.saves == [expected])
    }

    @Test("N1, R7. Changes made while a save runs wait for it, then are saved once, folded, the last value winning")
    func changesDuringASave_areFoldedIntoTheNext() async throws {
        let scene = SettingsScene(holdsSaves: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilASaveIsHeld()
        scene.store.send(.setPlateMath(false))
        scene.store.send(.setWeekStart(.friday))
        scene.store.send(.setWeekStart(.tuesday))
        let shown = try scene.model
        #expect(shown.weekStart.value == "Tuesday" && shown.units.options[1].isSelected)
        scene.watched.releaseSaves()
        await eventually { scene.store.pending == nil }
        var first = Fixtures.settingsLb
        first.units = .kg
        var folded = first
        folded.plateMathEnabled = false
        folded.weekStart = .tuesday
        #expect(scene.watched.saves == [first, folded])
        #expect(scene.watched.mostAtOnce == 1)
        #expect(try await scene.stored() == folded)
        #expect(try scene.model == shown, "the echo of the first save never drew over the lifter's value")
    }

    @Test("N1. The observation's echo of an earlier save does not move a control back")
    func earlierEcho_doesNotFlickerBack() async throws {
        let scene = SettingsScene(holdsSaves: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setWeekStart(.friday))
        await scene.untilASaveIsHeld()
        scene.store.send(.setWeekStart(.tuesday))
        scene.watched.releaseSaves(keepHolding: true)
        // The first save lands and the observation gives its value back while the second is held or on its way.
        await eventually { scene.store.stored?.weekStart == .friday }
        #expect(try scene.model.weekStart.value == "Tuesday")
        scene.watched.releaseSaves()
        await eventually { scene.store.pending == nil }
        #expect(try scene.model.weekStart.value == "Tuesday")
    }

    @Test("N1. A failed save shows its line and puts the stored value back; the next change clears the line")
    func failedSave_revertsAndSaysSo() async throws {
        let scene = SettingsScene(failures: 1)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setAutoRest(false))
        await eventually { scene.store.model?.problem != nil }
        let failed = try scene.model
        #expect(failed.problem == "Couldn't save that change.")
        #expect(failed.switches[1].isOn, "the switch shows the stored value again")
        #expect(try await scene.stored() == Fixtures.settingsLb)
        scene.store.send(.setWatchBuzz(false))
        #expect(try scene.model.problem == nil)
        await eventually { scene.store.pending == nil }
        var saved = Fixtures.settingsLb
        saved.watchBuzz = false
        #expect(try await scene.stored() == saved, "the failed change is not saved with the next")
    }
}
