@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S14, criterion 19: the library sheet's store, owned by the Day editor's store and driven through it,
/// as the root drives it. Every action is applied before `send` returns.
@MainActor
@Suite("ExercisePickerStore", .tags(.feature), .timeLimit(.minutes(1)))
struct ExercisePickerStoreTests {
    @Test(
        "19. \"Add\" appends the picks in order as one write, closes the sheet, empties query and picks, keeps chips"
    )
    func add_appendsInPickOrder_andKeepsTheFilters() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        scene.store.send(.openLibrary)
        #expect(scene.store.library.isShown)
        try scene.store.send(ExercisePickerAction.setMuscle(.legs))
        try scene.store.send(ExercisePickerAction.setEquipment(.barbell))
        scene.store.send(ExercisePickerAction.setQuery("squat"))
        #expect(try scene.library.search.query == "squat", "the query is the model's at once")
        let ids = try await [scene.exercise("Back Squat"), scene.exercise("Front Squat")]
        for id in ids.reversed() {
            scene.store.send(ExercisePickerAction.setPicked(true, exercise: id))
        }
        scene.store.send(ExercisePickerAction.setPicked(true, exercise: ids[1]))
        let add = try #require(scene.library.foot.action)
        #expect(add == .add(Array(ids.reversed())), "a pick tapped again keeps its place")
        scene.store.send(add)
        #expect(!scene.store.library.isShown)
        #expect(scene.store.library.query == "" && scene.store.library.picks == [])
        #expect(scene.store.library.muscle == .legs && scene.store.library.equipment == .barbell)
        #expect(try scene.content.rows.suffix(2).map(\.name) == ["Front Squat", "Back Squat"])
        #expect(try scene.library.rows.filter(\.isMarkedInDay).count == 2, "the day's new exercises are marked")
        await scene.idle()
        let stored = try #require(try await scene.storedDay())
        #expect(stored.slots.suffix(2).map(\.exerciseID) == Array(ids.reversed()))
        #expect(stored.slots.suffix(2).map(\.rest) == [
            Fixtures.settingsLb.defaultRest,
            Fixtures.settingsLb.defaultRest
        ])
        #expect(await scene.writes() == 1)
        await running.cancel()
    }

    @Test("19. \"Clear filters\" resets the query and both chips and keeps the picks")
    func clearFilters_resetsQueryMuscleAndEquipment() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        let squat = try await scene.exercise("Back Squat")
        scene.store.send(ExercisePickerAction.setPicked(true, exercise: squat))
        scene.store.send(ExercisePickerAction.setMuscle(.chest))
        scene.store.send(ExercisePickerAction.setEquipment(.cable))
        scene.store.send(ExercisePickerAction.setQuery("zzzz"))
        let clear = try #require(scene.library.empty?.clear.action)
        scene.store.send(clear)
        #expect(scene.store.library.query == "" && scene.store.library.muscle == nil)
        #expect(scene.store.library.equipment == nil && scene.store.library.picks == [squat])
        await running.cancel()
    }

    @Test("19. \"Cancel\" adds nothing, empties query and picks and keeps the chips, for the next opening")
    func cancel_addsNothing_andKeepsTheChips() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        scene.store.send(.openLibrary)
        scene.store.send(ExercisePickerAction.setMuscle(.back))
        scene.store.send(ExercisePickerAction.setQuery("row"))
        try await scene.store.send(ExercisePickerAction.setPicked(true, exercise: scene.exercise("Back Squat")))
        try scene.store.send(scene.library.cancel.action)
        #expect(!scene.store.library.isShown && scene.store.library.picks == [] && scene.store.library.query == "")
        scene.store.send(.openLibrary)
        #expect(try scene.library.muscles.chips.first(where: \.isSelected)?.title == "Back")
        await scene.idle()
        #expect(await scene.writes() == 0)
        await running.cancel()
    }

    @Test("19. An exercise saved while the sheet is open appears in it")
    func customExerciseSavedWhileOpen_appears() async throws {
        let scene = try DayEditorStoreScene()
        let running = await scene.running()
        scene.store.send(.openLibrary)
        scene.store.send(ExercisePickerAction.setQuery("Zercher"))
        #expect(try scene.library.rows.isEmpty)
        let custom = Exercise(
            id: ExerciseID(Fixtures.uuid(77001)), name: "Zercher Carry", shortName: "Zercher", equipment: .barbell,
            primaryMuscle: .quads, pattern: .carry, defaultStartLoad: [.lb: .pounds(95)], isCustom: true
        )
        try await scene.memory.exercises.save(custom)
        await eventually { scene.store.libraryModel?.rows.first?.name == "Zercher Carry" }
        await running.cancel()
    }

    @Test("19. An exercise gone since the pick is left out, and so is one whose slot cannot be made")
    func add_skipsWhatCannotBeAdded() async throws {
        let refused = Exercise(
            id: ExerciseID(Fixtures.uuid(77002)), name: "Negative Press", shortName: "Neg", equipment: .barbell,
            primaryMuscle: .chest, pattern: .horizontalPush, defaultStartLoad: [.lb: .pounds(-5)], isCustom: true
        )
        let scene = try DayEditorStoreScene(exercises: ExerciseCatalog.seed() + [refused])
        let running = await scene.running()
        let squat = try await scene.exercise("Back Squat")
        let stranger = ExerciseID(Fixtures.uuid(77003))
        scene.store.send(ExercisePickerAction.add([stranger, refused.id, squat]))
        #expect(try scene.content.rows.last?.name == "Back Squat")
        #expect(try scene.content.rows.count == 6)
        await running.cancel()
    }
}
