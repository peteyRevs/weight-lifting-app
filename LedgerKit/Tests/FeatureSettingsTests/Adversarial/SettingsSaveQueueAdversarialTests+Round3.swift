import Dependencies
@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// F14 S1a fix round 3, G3's round 2: retired observations are closed (R2-1), and the two conditions that no test
/// pinned (R2-2): a first value read before a save returned is not taken as the row, and a failed save still has the
/// row read afresh. G3's round 3: both run in GRDB's order, deterministically (R3-1, R3-2), and a retired
/// observation's value is never received (R3-3).
extension SettingsSaveQueueAdversarialTests {
    /// G3's probe P2 (R2-1). Each failing save restarts the observation; the retired one is cancelled, so the open
    /// observations stay at one, and at two only while one hands over to the next.
    @Test("R2-1. Twenty failing saves leave one observation open, never more than two")
    func failingSaves_leaveOneObservationOpen() async {
        let scene = ScriptedSettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        #expect(scene.repository.observationCount == 1)
        var most = 1
        for _ in 0 ..< 20 {
            scene.store.send(.setUnits(.kg))
            await scene.untilHeld()
            scene.repository.resolveNext(commit: false)
            await scene.until("failed") { scene.store.pending == nil && scene.repository.heldValues.isEmpty }
            for _ in 0 ..< 1000 {
                most = max(most, scene.repository.observationCount)
                await Task.yield()
            }
        }
        #expect(most <= 2, "at most two observations were open at once: \(most)")
        #expect(scene.repository.observationCount == 1)
    }

    /// G3's probe P3 (R2-2, M7). A change made just as the saver went idle starts a save that fails: the failure still
    /// has the row read afresh, so a change made elsewhere afterwards reaches the screen.
    ///
    /// The fresh read after the first save is held until the second save is running (F14-S1a-R3-2), so it always
    /// lands while `isSaving` and is never taken as the row: only the failure's own fresh read can show the change.
    @Test("R2-2. A save that fails before the fresh read still has the row read afresh")
    func failureBeforeTheFreshRead_stillReadsTheRow() async {
        let scene = ScriptedSettingsScene(holdsFirstValues: true)
        let task = Task { await scene.store.run() }
        defer { task.cancel() }
        await scene.until("the run's observation") { scene.repository.firstValuesWaiting == 1 }
        scene.repository.deliverNextFirstValue()
        await scene.until("the first model") { scene.store.model != nil }
        scene.store.send(.setUnits(.kg))
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true)
        await scene.until("idle, the fresh read held") {
            scene.store.pending == nil && scene.repository.firstValuesWaiting == 1
        }
        scene.store.send(.setWeekStart(.friday))
        await scene.untilHeld()
        scene.repository.deliverNextFirstValue() // the read after the first save, received during the second
        await scene.until("the read is received") { scene.store.stored == Self.kilograms }
        let stillWritten = scene.store.written == Self.kilograms
        #expect(stillWritten, "a read received while a save runs is not taken as the row")
        scene.repository.resolveNext(commit: false)
        await scene.until("failed") { scene.store.pending == nil && scene.repository.heldValues.isEmpty }
        await scene.until("the failure's fresh read") { scene.repository.firstValuesWaiting == 1 }
        scene.repository.deliverNextFirstValue()
        await scene.yieldALot()
        var elsewhere = Self.kilograms
        elsewhere.weekStart = .thursday
        scene.repository.writeElsewhere(elsewhere)
        await scene.until("the change is read") { scene.store.stored == elsewhere }
        await scene.yieldALot()
        let shownIsTheRow = scene.store.shown == elsewhere
        #expect(shownIsTheRow, "the screen shows the other writer's Thursday")
    }

    /// R2-2 (M1, M11). An observation's first value is read when it starts and delivered later, as GRDB delivers it.
    /// The restart after A's save starts observation D, which reads A. B is then saved; D's read of A arrives after
    /// B's save returned and before the follower handles B's restart, with B's echo right behind it, in order
    /// (F14-S1a-R3-1). It is older than the row, and must not flash A over B: the model never changes.
    ///
    /// On the main actor that window is a GRDB delivery that lands while the saver's tail runs. The test holds it
    /// open by keeping the restart mark from the follower until D's values are received, then hands the mark back.
    @Test("R2-2. A first value read before a save returned is not taken as the row")
    func firstValueReadBeforeASave_isNotTheRow() async throws {
        let scene = ScriptedSettingsScene(holdsFirstValues: true)
        let task = Task { await scene.store.run() }
        defer { task.cancel() }
        await scene.until("the run's observation") { scene.repository.firstValuesWaiting == 1 }
        scene.repository.deliverNextFirstValue()
        await scene.until("the first model") { scene.store.model != nil }
        scene.store.send(.setUnits(.kg)) // A
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true)
        await scene.until("A's restart starts D, which reads A") {
            scene.store.pending == nil && scene.repository.firstValuesWaiting == 1
        }
        let restart = try #require(scene.store.followMark)
        scene.store.followMark = nil // B's restart waits
        scene.store.send(.setWeekStart(.friday)) // B
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true)
        await scene.until("B is written") { scene.store.pending == nil && !scene.store.isSaving }
        let echoWaitsBehindTheRead = scene.store.stored == Self.kilograms
        #expect(echoWaitsBehindTheRead, "B's echo has not overtaken D's read of A")
        let modelChanged = LockIsolated(false)
        withObservationTracking { _ = scene.store.model } onChange: { modelChanged.setValue(true) }
        scene.repository.deliverNextFirstValue() // D's read of A, older than the row, then B's echo
        var savedB = Self.kilograms
        savedB.weekStart = .friday
        await scene.until("D's read and B's echo are received") { scene.store.stored == savedB }
        #expect(!modelChanged.value, "D's read, older than the row, did not flash A over B")
        let shownIsB = scene.store.shown == savedB
        #expect(shownIsB)
        scene.store.followMark = restart
        restart.yield()
        await scene.until("B's restart reads B") { scene.repository.firstValuesWaiting == 1 }
        scene.repository.deliverNextFirstValue()
        await scene.until("the row is read afresh") { scene.store.written == nil }
        let stillB = scene.store.shown == savedB
        #expect(stillB)
    }

    /// F14-S1a-R3-3 (M4). Between the follower retiring an observation and its cancellation landing, a value already
    /// on its way may still reach the old observation's loop; its number keeps it from being received. The test
    /// keeps the first observation's retire handle from the follower, so that window stays open: the old
    /// observation then hears A's held echo after the row was read afresh at B, and must not draw A over B.
    @Test("R3-3. A value of a retired observation is never received")
    func retiredObservationsValue_isNeverReceived() async throws {
        let scene = ScriptedSettingsScene(holdsEchoes: true)
        let task = await scene.running()
        defer { task.cancel() }
        let retire = try #require(scene.store.retireObservation)
        scene.store.retireObservation = nil // the first observation stays open after it is retired
        defer { retire.finish() }
        scene.store.send(.setUnits(.kg)) // A: its echo is held for the first observation
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true)
        await scene.until("A is written") { scene.store.pending == nil && !scene.store.isSaving }
        scene.store.send(.setWeekStart(.friday)) // B
        await scene.untilHeld()
        scene.repository.resolveNext(commit: true)
        var savedB = Self.kilograms
        savedB.weekStart = .friday
        await scene.until("the row is read afresh at B") {
            scene.store.observationNumber == 3 && scene.store.written == nil && scene.store.stored == savedB
        }
        scene.repository.deliverNextEcho() // A's echo, to the first observation only
        await scene.yieldALot()
        let shownIsB = scene.store.shown == savedB
        #expect(shownIsB, "the retired observation's echo of A was not drawn over B")
    }
}
