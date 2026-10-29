@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S1a fix round 2, G3's review: the row read afresh when the saver goes idle (R1-1), and the two branches no
/// test pinned (R1-2), over `ScriptedSettings`.
extension SettingsSaveQueueAdversarialTests {
    // MARK: Fix round 2 (G3, F14-S1a-R1-1 and R1-2)

    /// Kilograms with Plate math off: B of G3's A, B, A script, where A is kilograms with Plate math on.
    static var kilogramsNoPlates: Settings {
        var settings = kilograms
        settings.plateMathEnabled = false
        return settings
    }

    /// Saves A (KG), B (Plate math off) and A again (Plate math on), each committed with its echo held, and waits
    /// for the idle saver's fresh read.
    fileprivate static func savedABA(_ scene: ScriptedSettingsScene) async {
        for action in [SettingsAction.setUnits(.kg), .setPlateMath(false), .setPlateMath(true)] {
            scene.store.send(action)
            await scene.untilHeld()
            scene.repository.resolveNext(commit: true)
            await scene.until("written") { scene.repository.heldValues.isEmpty && scene.store.pending == nil }
        }
        await scene.until("the row is read afresh") { scene.store.written == nil }
    }

    /// G3's probe of R1-1. A coalesced echo once left a stale entry in the store's list, and a change made elsewhere
    /// that equalled it was taken for an echo: the screen kept Plate math on while the row had it off.
    @Test("R1-1. After a coalesced echo, a change made elsewhere is drawn as the row holds it")
    func coalescedEcho_thenAChangeElsewhere_drawsTheRow() async {
        let scene = ScriptedSettingsScene(holdsEchoes: true)
        let task = await scene.running()
        defer { task.cancel() }
        await Self.savedABA(scene)
        scene.repository.deliverNewestEcho()
        scene.repository.writeElsewhere(Self.kilogramsNoPlates)
        await scene.until("the change is read") { scene.store.stored == Self.kilogramsNoPlates }
        let shownIsTheRow = scene.store.shown == scene.repository.row
        #expect(shownIsTheRow, "the screen shows Plate math off, as the row has it")
        scene.store.send(.setWeekStart(.friday))
        await scene.untilHeld()
        var expected = Self.kilogramsNoPlates
        expected.weekStart = .friday
        let savesOverTheRow = scene.repository.heldValues.first == expected
        #expect(savesOverTheRow, "the next change is saved over the other writer's value")
        scene.repository.resolveNext(commit: true)
    }

    /// G3's in-order script: the echoes of A, B and A, delivered one by one after all three were written, never draw
    /// B (the flash a last-match rule would bring back).
    @Test("R1-1. The echoes of A, B, A delivered in order after the three saves never draw B")
    func echoesABA_inOrder_neverDrawB() async {
        let scene = ScriptedSettingsScene(holdsEchoes: true)
        let task = await scene.running()
        defer { task.cancel() }
        await Self.savedABA(scene)
        var drewB = false
        while scene.repository.echoesWaiting > 0 {
            scene.repository.deliverNextEcho()
            await scene.yieldALot()
            drewB = drewB || scene.store.shown == Self.kilogramsNoPlates
        }
        #expect(!drewB)
        let shownIsA = scene.store.shown == Self.kilograms
        #expect(shownIsA)
    }

    /// R1-2's first case, in the new design: a change made elsewhere while this store's echo is held is drawn once
    /// the saver is idle and the row is read afresh, and nothing of this store's is left to draw over it. (The FIFO's
    /// `else { unechoed = [] }` branch, M3, went with the FIFO.)
    @Test("R1-2. A change made elsewhere after a save whose echo is held is what the screen shows")
    func changeElsewhere_afterAHeldEcho_isShown() async {
        let scene = ScriptedSettingsScene(holdsEchoes: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true)
        await scene.until("the row is read afresh") { scene.store.pending == nil && scene.store.written == nil }
        var elsewhere = Self.kilograms
        elsewhere.weekStart = .thursday
        scene.repository.writeElsewhere(elsewhere)
        await scene.until("the change is read") { scene.store.stored == elsewhere }
        let shownIsTheRow = scene.store.shown == elsewhere
        #expect(shownIsTheRow)
        #expect(scene.store.written == nil)
    }

    /// R1-2's second case, G3's test (M5): a change queued behind a save when the run is cancelled is handed to the
    /// new run, which saves it once the old run's save has returned.
    @Test("R1-2. A change queued behind a save when the run restarts is saved by the new run")
    func restart_handsTheQueuedChangeToTheNewRun() async {
        let scene = ScriptedSettingsScene()
        let first = await scene.running()
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.store.send(.setWeekStart(.friday))
        first.cancel()
        let second = Task { await scene.store.run() }
        defer { second.cancel() }
        await scene.yieldALot()
        scene.repository.resolveNext(commit: true) // KG commits in the cancelled run
        await first.value
        await scene.untilHeld()
        var friday = Self.kilograms
        friday.weekStart = .friday
        let nextIsFriday = scene.repository.heldValues.first == friday
        #expect(nextIsFriday, "the new run saves the queued change")
        scene.repository.resolveNext(commit: true)
        await scene.until("nothing pending") { scene.store.pending == nil }
        let rowIsFriday = scene.repository.row == friday
        #expect(rowIsFriday)
        #expect(scene.repository.mostAtOnce == 1)
    }
}
