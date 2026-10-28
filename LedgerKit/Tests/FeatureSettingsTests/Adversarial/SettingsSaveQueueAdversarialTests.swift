@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S1a, G2: R7's save queue under attack. Each save is held until the test ends it, and in the echo tests the
/// observation's values are held too, as GRDB's `.task`-scheduled observation sends a commit's value after
/// `write` has returned to the saver.
@MainActor
@Suite("Settings' save queue, adversarial", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct SettingsSaveQueueAdversarialTests {
    static var kilograms: Settings {
        var settings = Fixtures.settingsLb
        settings.units = .kg
        return settings
    }

    // MARK: Pins

    @Test("Pin. A failed save after a successful one leaves the row at the successful one, and nothing else is saved")
    func failAfterSuccess_rowKeepsTheSuccess() async {
        let scene = ScriptedSettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.store.send(.setWeekStart(.friday))
        scene.repository.resolveNext(commit: true)
        await scene.untilHeld()
        scene.repository.resolveNext(commit: false)
        await scene.until("the failure is drawn") { scene.store.model?.problem != nil }
        await scene.settle()
        let rowIsKilograms = scene.repository.row == Self.kilograms
        let shownIsKilograms = scene.store.shown == Self.kilograms
        #expect(rowIsKilograms)
        #expect(shownIsKilograms)
        #expect(scene.repository.saves.count == 2)
        #expect(scene.repository.mostAtOnce == 1)
    }

    @Test("Pin. A tap that puts back the stored value while its change is being saved saves the stored value again")
    func tapBack_duringSave_savesTheStoredValue() async throws {
        let scene = ScriptedSettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.store.send(.setUnits(.lb))
        #expect(try #require(scene.store.model).units.options[0].isSelected)
        scene.repository.resolveNext(commit: true)
        await scene.untilHeld()
        let heldIsPounds = scene.repository.heldValues == [Fixtures.settingsLb]
        #expect(heldIsPounds, "the row holds kg: lb must be written back")
        scene.repository.resolveNext(commit: true)
        await scene.settle()
        await scene.until("nothing pending") { scene.store.pending == nil }
        let rowIsPounds = scene.repository.row == Fixtures.settingsLb
        let shownIsPounds = scene.store.shown == Fixtures.settingsLb
        #expect(rowIsPounds)
        #expect(shownIsPounds)
    }

    // MARK: Findings

    /// F14-S1-1 (ruled, 2026-10-28). A change made while a save runs is folded into the next save; when the running
    /// save fails, the whole screen goes back to what is committed and the changes queued behind it are dropped with
    /// it, untried, under "Couldn't save that change." (N1).
    @Test("F14-S1-1. A save that fails drops the change made during it and puts back what is committed")
    func changeDuringAFailingSave_isDroppedWithIt() async {
        let scene = ScriptedSettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.store.send(.setPlateMath(false))
        scene.repository.resolveNext(commit: false)
        await scene.until("the failure is drawn") { scene.store.model?.problem != nil }
        // Let any save that is coming start.
        for _ in 0 ..< 1000 {
            await Task.yield()
        }
        #expect(scene.repository.saves.count == 1, "the queued change is not tried")
        #expect(scene.repository.heldValues.isEmpty)
        let shownIsCommitted = scene.store.shown == Fixtures.settingsLb
        #expect(shownIsCommitted, "units and Plate math both show what is committed")
        #expect(scene.store.pending == nil)
        #expect(scene.store.model?.problem == "Couldn't save that change.")
    }

    /// F14-S1-2 (fixed in S1a fix round 1; the test describes the defect it pins against). A failed save puts back
    /// `stored`, the observation's last value. When an earlier save of the same
    /// run has committed and its echo has not arrived yet, `stored` is older than the row: the screen shows a
    /// value that is not saved, and the lifter's next change saves it, undoing the committed change.
    @Test("F14-S1-2. After a failure the screen shows the row, not an older echo, and the next change keeps the row")
    func failure_beforeTheEarlierEcho_revertsToTheRow() async {
        let scene = ScriptedSettingsScene(holdsEchoes: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.store.send(.setWeekStart(.friday))
        scene.repository.resolveNext(commit: true) // the row is kg; its echo waits
        await scene.untilHeld()
        scene.repository.resolveNext(commit: false)
        await scene.until("the failure is drawn") { scene.store.model?.problem != nil }
        #expect(scene.repository.row.units == .kg)
        #expect(scene.store.shown?.units == .kg)
        scene.store.send(.setPlateMath(false))
        await scene.untilHeld()
        #expect(scene.repository.heldValues.first?.units == .kg)
        scene.repository.resolveNext(commit: true)
        while scene.repository.echoesWaiting > 0 {
            scene.repository.deliverNextEcho()
            await Task.yield()
        }
    }

    /// F14-S1-3 (fixed in S1a fix round 1; the test describes the defect it pins against). A save that leaves `pending`
    /// equal to `stored` clears `pending` at once, because no echo will
    /// come for it. But the echo of an EARLIER save of the run may still be on its way: it then arrives with
    /// nothing pending and is drawn, so the control flickers back to a value the lifter already changed (N1).
    @Test("F14-S1-3. A late echo of an earlier save never draws over the lifter's last value")
    func lateEcho_afterTapBack_doesNotFlicker() async {
        let scene = ScriptedSettingsScene(holdsEchoes: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true) // kg is saved; its echo waits
        await scene.until("kg written") { scene.repository.row.units == .kg && scene.repository.heldValues.isEmpty }
        scene.store.send(.setUnits(.lb))
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true) // lb is saved; pending == stored, so pending is cleared
        await scene.until("the store forgets lb as pending") { scene.store.pending == nil }
        #expect(scene.store.model?.units.options[0].isSelected == true, "LB, the lifter's last tap")
        scene.repository.deliverNextEcho() // kg's late echo
        await scene.until("the echo is read") { scene.store.stored?.units == .kg }
        #expect(scene.store.model?.units.options[0].isSelected == true)
        scene.repository.deliverNextEcho()
        await scene.until("lb's echo is read") { scene.store.stored?.units == .lb }
        #expect(scene.store.model?.units.options[0].isSelected == true)
    }

    /// F14-S1-4 (fixed in S1a fix round 1; the test describes the defect it pins against). The root's task restarts on
    /// the same `@State` store (a tab switched away and back). The first
    /// run, cancelled mid-save, cannot end until that save returns; the second run starts a save of its own
    /// beside it (R7: one at a time), and when the first ends it sets `saveMark` and `followMark` to nil, which
    /// are now the second run's. Every later change is drawn and never saved while the screen stays up.
    @Test("F14-S1-4. A run restarted during a save saves one at a time, and keeps saving later changes")
    func restartDuringASave_keepsSaving() async {
        let scene = ScriptedSettingsScene()
        let first = await scene.running()
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        first.cancel()
        let second = Task { await scene.store.run() }
        defer { second.cancel() }
        // The second run's start: it finds the change pending. Bounded: no second save comes while the first runs.
        for _ in 0 ..< 200_000 where scene.repository.heldValues.count < 2 {
            await Task.yield()
        }
        #expect(scene.repository.mostAtOnce == 1)
        while !scene.repository.heldValues.isEmpty {
            scene.repository.resolveNext(commit: true)
            await Task.yield()
        }
        await first.value
        await scene.until("kg settles") { scene.store.pending == nil && scene.repository.heldValues.isEmpty }
        let before = scene.repository.saves.count
        scene.store.send(.setWeekStart(.friday))
        for _ in 0 ..< 200_000 where scene.repository.saves.count == before {
            await Task.yield()
        }
        #expect(scene.store.saveMark != nil)
        #expect(scene.repository.saves.count > before)
        scene.repository.resolveNext(commit: true)
    }
}
