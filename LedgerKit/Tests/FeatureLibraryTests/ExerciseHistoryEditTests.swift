@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S3, criterion 10 and N13 through the history's store: "Edit" puts the sheet up on the lifter's own exercise as
/// stored, its close takes it down, and a catalog exercise is never edited; a saved rename shows on the open history.
@MainActor
@Suite("ExerciseHistoryStore · Edit", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct ExerciseHistoryEditTests {
    @Test("10. Edit opens the sheet on the lifter's own exercise; closing it takes it down")
    func edit_custom_opensAndCloses() async throws {
        let scene = try HistoryScene(exercise: LibraryFixtures.custom.id)
        try await scene.memory.exercises.save(LibraryFixtures.custom)
        let run = await scene.running()
        defer { run.cancel() }
        await eventually { (try? scene.model.edit) == "Edit" }
        scene.store.edit()
        #expect(scene.store.editedExercise == LibraryFixtures.custom)
        scene.store.editClosed()
        #expect(scene.store.editedExercise == nil)
    }

    @Test("10. A catalog exercise's history has no Edit, and asking for one opens nothing")
    func edit_catalog_opensNothing() async throws {
        let scene = try HistoryScene()
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.edit == nil)
        scene.store.edit()
        #expect(scene.store.editedExercise == nil)
    }

    @Test("N13. An edit saved from the sheet renames the open history")
    func editSaved_renamesTheHistory() async throws {
        let scene = try HistoryScene(exercise: LibraryFixtures.custom.id)
        try await scene.memory.exercises.save(LibraryFixtures.custom)
        let run = await scene.running()
        defer { run.cancel() }
        await eventually { (try? scene.model.title) == LibraryFixtures.custom.name }
        scene.store.edit()
        let sheet = withTestDependencies {
            $0.exerciseRepository = scene.memory.exercises
        } operation: {
            CreateExerciseStore(editing: scene.store.editedExercise)
        }
        sheet.send(.setName("Landmine Press, Kneeling"))
        sheet.send(.setEquipment(.dumbbell))
        sheet.send(.save)
        await sheet.save()
        #expect(sheet.phase == .saved)
        await eventually { (try? scene.model.title) == "Landmine Press, Kneeling" }
        #expect(try scene.model.eyebrow == "Dumbbell · Chest")
    }
}
