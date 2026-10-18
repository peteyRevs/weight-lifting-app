@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13, criterion 6 (ruling R1): a write whose task is cancelled stores all of its edits or none, and the
/// store keeps what was not stored and sends it once.
extension ProgramEditSessionTests {
    // MARK: Criterion 6

    @Test("6. The view goes away during a save (cancelled from inside its change): nothing is stored, nothing failed")
    func viewGoesAwayDuringASave_storesAllOrNothing() async throws {
        var cancelling: CancellingPrograms?
        let scene = try ProgramStoreScene { values, probed in
            let wrapped = CancellingPrograms(base: probed.programs)
            cancelling = wrapped
            values.programRepository = wrapped
        }
        let cancel = try #require(cancelling).cancel
        let sources = Task { await scene.store.run() }
        await eventually { scene.store.state != .loading }
        let saving = cancel.run { await scene.store.save() }
        try scene.store.send(scene.model.block.addWeek)
        _ = await saving.result
        #expect(try await scene.stored().weeks.count == 8, "nothing was stored")
        #expect(scene.store.session.waiting.count == 1, "the edit waits to be sent again")
        #expect(try scene.model.block.chips.count == 9 && scene.model.notice == nil, "and nothing is shown as failed")

        let again = Task { await scene.store.save() }
        await scene.idle()
        #expect(try await scene.stored().weeks.count == 9, "the week is added once")
        sources.cancel()
        again.cancel()
    }

    @Test("6. A held write whose task is cancelled stores nothing; the next run removes the last week once")
    func viewGoesAwayDuringAHeldSave_theNextRunSendsItOnce() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        try scene.store.send(scene.model.block.removeWeek)
        try await scene.probe.waitUntilHeld()
        running.saving.cancel()
        await scene.probe.release()
        await running.saving.value
        #expect(try await scene.stored().weeks.count == 8)
        #expect(scene.store.session.waiting.count == 1)
        #expect(try scene.model.notice == nil)

        let again = Task { await scene.store.save() }
        await scene.idle()
        #expect(try await scene.stored().weeks.count == 7, "removed once, not twice")
        #expect(await scene.writes() == 2)
        running.sources.cancel()
        again.cancel()
    }

    @Test("6. A write that returns although its task was cancelled stored everything: it is not sent again")
    func cancelledOnceStored_isNotSentAgain() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram, afterStoring: true)
        try scene.store.send(scene.model.block.addWeek)
        try await scene.probe.waitUntilHeld()
        running.saving.cancel()
        await scene.probe.release()
        await running.saving.value
        #expect(scene.store.session.isIdle)
        let again = Task { await scene.store.save() }
        await scene.idle()
        #expect(await scene.writes() == 1)
        #expect(try await scene.stored().weeks.count == 9)
        running.sources.cancel()
        again.cancel()
    }
}
