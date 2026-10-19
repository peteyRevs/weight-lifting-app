@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S14, criteria 16 and 17: when the Day editor closes. Its day gone, "Done" and "Program" hand the app one
/// `.closeDay`, once nothing waits to be stored; a write that fails keeps the editor open and says so.
extension DayEditorStoreTests {
    // MARK: Criterion 16

    @Test("16. After \"Delete\" the day is gone and the editor closes once the write that removes it has returned")
    func delete_closesOnceItsWriteReturned() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        try scene.store.send(scene.content.deleteDay.confirmation.confirm.action)
        #expect(scene.store.state == .dayIsGone)
        try await scene.probe.waitUntilHeld()
        #expect(scene.store.pendingRoute == nil, "the day is not deleted yet")
        await scene.probe.release()
        await eventually { scene.store.pendingRoute != nil }
        var handed: [ProgramRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.closeDay])
        #expect(try await scene.storedDay() == nil)
        await running.cancel()
    }

    @Test("16. A day deleted elsewhere closes the editor, once")
    func dayRemovedElsewhere_closesTheEditor() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        let day = scene.store.day
        _ = try await scene.memory.programs.update(scene.program.id) { ProgramEditing.deleteDay($0, day: day) }
        await eventually { scene.store.pendingRoute != nil }
        #expect(scene.store.state == .dayIsGone)
        scene.store.deliverRoute { _ in }
        try await scene.memory.programs.save(scene.program)
        _ = try await scene.memory.programs.update(scene.program.id) { ProgramEditing.deleteDay($0, day: day) }
        await eventually { scene.store.state == .dayIsGone }
        #expect(scene.store.pendingRoute == nil, "the editor closes once")
        await running.cancel()
    }

    @Test("16. The day is judged only once the store has said which program is active")
    func dayIsGone_isJudgedOnlyAfterTheFirstProgram() async throws {
        let scene = try DayEditorStoreScene(dayIndex: nil)
        scene.store.send(.route(.closeDay))
        #expect(scene.store.pendingRoute?.route == .closeDay, "a tap on Done with nothing to store closes")
        let unknown = try DayEditorStoreScene(dayIndex: nil)
        #expect(unknown.store.pendingRoute == nil && unknown.store.state == .loading)
        let running = await unknown.running()
        #expect(unknown.store.state == .dayIsGone)
        #expect(unknown.store.pendingRoute?.route == .closeDay)
        await running.cancel()
    }

    // MARK: Criterion 17

    @Test("17. \"Done\" waits for the write in flight and the edits behind it; tapped twice it is one route")
    func done_waitsForTheWrite() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        scene.store.send(.rename("Push", day: scene.store.day))
        try await scene.probe.waitUntilHeld()
        scene.store.send(.rename("Push A", day: scene.store.day))
        try scene.store.send(scene.content.header.done.action)
        try scene.store.send(scene.content.header.back.action)
        #expect(scene.store.pendingRoute == nil)
        await scene.probe.release()
        await eventually { scene.store.pendingRoute != nil }
        #expect(scene.store.session.isIdle)
        #expect(try await scene.storedDay()?.name == "Push A")
        var handed: [ProgramRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.closeDay])
        await running.cancel()
    }

    @Test("17. A write that fails drops the close, shows the stored day and says so; the next \"Done\" closes")
    func failedWrite_dropsTheClose_andSaysSo() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        await scene.probe.fail(.updateProgram)
        scene.store.send(.rename("Push", day: scene.store.day))
        try scene.store.send(scene.content.header.done.action)
        await scene.idle()
        #expect(scene.store.showsSaveFailure)
        #expect(scene.store.pendingRoute == nil && !scene.store.isClosing)
        #expect(try scene.content.header.name == "Upper A — Push focus", "the day as stored")
        scene.store.showsSaveFailure = false
        try scene.store.send(scene.content.header.done.action)
        #expect(scene.store.pendingRoute?.route == .closeDay)
        await running.cancel()
    }

    @Test("17. A failed \"Delete\" brings the day back and does not close")
    func failedDelete_bringsTheDayBack() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        await scene.probe.fail(.updateProgram)
        try scene.store.send(scene.content.deleteDay.confirmation.confirm.action)
        await scene.idle()
        #expect(try scene.content.header.name == "Upper A — Push focus")
        #expect(scene.store.showsSaveFailure && scene.store.pendingRoute == nil)
        await running.cancel()
    }

    @Test("17. The view goes away during a save (ruling R5): nothing of the write is stored, and nothing failed")
    func viewGoesAwayDuringASave_storesAllOrNothing() async throws {
        var cancelling: CancellingPrograms?
        let scene = try DayEditorStoreScene { values, probed in
            let wrapped = CancellingPrograms(base: probed.programs)
            cancelling = wrapped
            values.programRepository = wrapped
        }
        let cancel = try #require(cancelling).cancel
        let sources = Task { await scene.store.run() }
        await eventually { scene.store.state != .loading }
        let saving = cancel.run { await scene.store.save() }
        try scene.store.send(scene.content.row("2").action)
        try scene.store.send(#require(scene.content.openRow?.panel?.moveUp?.action))
        _ = await saving.result
        #expect(try await scene.storedDay()?.slots.map(\.id) == scene.program.days[0].slots.map(\.id))
        #expect(!scene.store.showsSaveFailure)
        sources.cancel()
        await sources.value
    }

    @Test("17. A write that fails while the library is up closes the sheet, and says so once the sheet is down")
    func failedWrite_whileTheLibraryIsUp_closesItAndSaysSoAfter() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        await scene.probe.fail(.updateProgram)
        scene.store.send(.openLibrary)
        scene.store.send(.rename("Push", day: scene.store.day))
        await scene.idle()
        #expect(!scene.store.library.isShown, "the sheet is closed")
        #expect(!scene.store.showsSaveFailure, "not under the sheet, where it would not be seen")
        scene.store.libraryClosed()
        #expect(scene.store.showsSaveFailure)
        scene.store.showsSaveFailure = false
        scene.store.libraryClosed()
        #expect(!scene.store.showsSaveFailure, "said once")
        await running.cancel()
    }
}
