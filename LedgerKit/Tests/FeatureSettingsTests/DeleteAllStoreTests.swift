@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S3, criterion 6 and N19–N23, the store: the warning, the typed word, the erase once, a failure, a cancellation,
/// a live workout, and the export's directory, over the in-memory stores the scene erases.
@MainActor
@Suite("SettingsStore · Delete all data", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct DeleteAllStoreTests {
    // MARK: The steps

    @Test("The row opens the warning; Cancel there closes it and deletes nothing")
    func warning_cancel_deletesNothing() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        let warning = try #require(try scene.model.deleteWarning)
        #expect(warning.title == "Delete all data?")
        #expect(warning.cancel.action == .cancelDeleteAll && warning.proceed.action == .continueDeleteAll)
        #expect(try scene.model.deleteSheet == nil)
        scene.store.send(warning.cancel.action)
        #expect(try scene.model.deleteWarning == nil && scene.model.deleteSheet == nil)
        #expect(reset.calls.isEmpty)
    }

    @Test("Continue opens the sheet; Cancel there, or a swipe, closes it and deletes nothing")
    func sheet_cancel_deletesNothing() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores()
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        #expect(try scene.model.deleteWarning == nil)
        let sheet = try #require(try scene.model.deleteSheet)
        #expect(sheet.prompt == "Type DELETE to confirm" && sheet.word == "DELETE" && sheet.confirm == nil)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.cancelDeleteAll)
        #expect(try scene.model.deleteSheet == nil)
        scene.store.send(.confirmDeleteAll)
        #expect(reset.calls.isEmpty)
        let workouts = try await scene.memory.workouts.recent(limit: 100)
        #expect(!workouts.isEmpty)
    }

    @Test(
        "Criterion 6.2. Delete everything acts only on the word, ignoring case and the spaces around it",
        arguments: [
            ("", false), ("DELET", false), ("DELETE IT", false), ("D ELETE", false), ("DELETED", false),
            ("DELETE", true), ("delete", true), ("Delete", true), ("  DeLeTe \n", true)
        ]
    )
    func typedWord_mustMatch(_ text: String, _ matches: Bool) async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(holds: true)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText(text))
        #expect(try (scene.model.deleteSheet?.confirm != nil) == matches)
        scene.store.send(.confirmDeleteAll)
        #expect(scene.store.deleteAll?.isErasing == matches)
        if matches {
            await DeleteAllScene.untilHeld(reset)
        }
        #expect(reset.calls.count == (matches ? 1 : 0))
        reset.release()
    }

    // MARK: The erase

    @Test("Criterion 6.3, N22. Confirmed, the erase runs once with the region's settings; then the export is gone")
    func confirm_erasesOnce_restoresTheRegion_andRemovesTheExport() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(holds: true)
        let task = await scene.running()
        defer { task.cancel() }
        try FileManager.default.createDirectory(at: scene.exportDirectory, withIntermediateDirectories: true)
        try Data("log".utf8).write(to: scene.exportDirectory.appending(path: "workouts-2026-09-16.csv"))
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.confirmDeleteAll)
        await DeleteAllScene.untilHeld(reset)
        // N23: a second tap, and the field and Cancel, do nothing while the erase runs.
        let sheet = try #require(try scene.model.deleteSheet)
        #expect(sheet.confirm == nil && sheet.isErasing)
        scene.store.send(.confirmDeleteAll)
        scene.store.send(.setDeleteText("x"))
        scene.store.send(.cancelDeleteAll)
        #expect(scene.store.deleteAll?.text == "DELETE" && scene.store.deleteAll?.isErasing == true)
        reset.release()
        await eventually { scene.store.deleteAll == nil }
        #expect(reset.calls.count == 1)
        let restored = reset.calls.first == DeleteAllScene.regional
        #expect(restored, "the erase restores a new US install's settings")
        #expect(!FileManager.default.fileExists(atPath: scene.exportDirectory.path(percentEncoded: false)))
        let workouts = try await scene.memory.workouts.recent(limit: 100)
        let catalog = try await scene.memory.exercises.all().count
        let bundled = try ExerciseCatalog.seed().count
        #expect(workouts.isEmpty && catalog == bundled)
        let stored = try await scene.stored() == DeleteAllScene.regional
        #expect(stored)
        await eventually { scene.store.stored == DeleteAllScene.regional }
    }

    @Test("Criterion 6.5. A failed erase keeps the sheet and says nothing was deleted; Try again by tapping again")
    func failure_keepsTheSheet() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(failures: 1)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("delete"))
        scene.store.send(.confirmDeleteAll)
        await eventually { scene.store.deleteAll?.failed == true }
        let sheet = try #require(try scene.model.deleteSheet)
        #expect(sheet.problem == "Nothing was deleted. Try again.")
        #expect(sheet.confirm == .confirmDeleteAll && sheet.text == "delete" && !sheet.isErasing)
        let workouts = try await scene.memory.workouts.recent(limit: 100)
        #expect(!workouts.isEmpty, "nothing was deleted")
        scene.store.send(.confirmDeleteAll)
        await eventually { scene.store.deleteAll == nil }
        #expect(reset.calls.count == 2)
        #expect(try await scene.memory.workouts.recent(limit: 100).isEmpty)
    }

    @Test("N23. An erase whose task is cancelled reports nothing, and the button acts again")
    func cancellation_reportsNothing() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(holds: true)
        let task = await scene.running()
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.confirmDeleteAll)
        await DeleteAllScene.untilHeld(reset)
        task.cancel()
        reset.release()
        await eventually { scene.store.deleteAll?.isErasing == false }
        #expect(scene.store.deleteAll?.failed == false)
        #expect(scene.store.model?.deleteSheet?.confirm == .confirmDeleteAll)
        let workouts = try await scene.memory.workouts.recent(limit: 100)
        #expect(!workouts.isEmpty, "the held erase was cancelled before it began")
    }

    @Test("Delete everything with no run of the screen's task asks for nothing, and the button does not stick")
    func confirmWithoutARun_erasesNothing() async throws {
        let (scene, reset) = try DeleteAllScene.erasingTheScenesStores()
        scene.store.send(.deleteAll)
        scene.store.send(.continueDeleteAll)
        scene.store.send(.setDeleteText("DELETE"))
        scene.store.send(.confirmDeleteAll)
        #expect(scene.store.deleteAll?.isErasing == false)
        #expect(reset.calls.isEmpty)
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.confirmDeleteAll)
        await eventually { scene.store.deleteAll == nil }
        #expect(reset.calls.count == 1)
    }
}
