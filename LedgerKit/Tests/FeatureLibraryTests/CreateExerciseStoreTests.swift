import Dependencies
@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S3, criteria 9 and 10 and N15–N17, through the store over in-memory stores: a save stores the exercise once
/// and closes the sheet; a rule broken shows under its field and keeps the sheet; an edit of the lifter's own
/// exercise stores it under its id, and a catalog exercise is never saved; a double tap, a failure and a
/// cancellation.
@MainActor
@Suite("CreateExerciseStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct CreateExerciseStoreTests {
    @Test("9. Save stores the lifter's exercise once, as chosen, with Q4's start of 0, and closes the sheet")
    func save_insertsAndCloses() async throws {
        let scene = CreateScene()
        scene.fillCriterion9()
        #expect(scene.store.model.title == "New exercise")
        scene.store.send(.save)
        #expect(scene.store.phase == .saving && scene.store.attempt == 1)
        #expect(scene.store.model.foot.action == nil, "Save is disabled while it runs")
        await scene.store.save()
        #expect(scene.store.phase == .saved)
        #expect(scene.exercises.saves.count == 1)
        let stored = try #require(try await scene.stored("Landmine Squeeze Press 2"))
        #expect(stored.isCustom && stored.shortName == stored.name && stored.curatedAlternatives.isEmpty)
        #expect(stored.equipment == .barbell && stored.primaryMuscle == .chest && stored.pattern == .horizontalPush)
        #expect(stored.secondaryMuscles == [.shoulders, .triceps])
        #expect(stored.startLoad(in: .lb) == .zero && stored.startLoad(in: .kg) == .zero)
    }

    @Test("9. The saved exercise appears in the Library's ALL EXERCISES as Barbell · Chest · Custom")
    func save_appearsInTheLibrary() async throws {
        let library = LibraryScene()
        let run = await library.running()
        defer { run.cancel() }
        let store = withTestDependencies {
            $0.exerciseRepository = library.memory.exercises
            $0.uuid = .incrementing
        } operation: {
            CreateExerciseStore()
        }
        store.send(.setName("Landmine Squeeze Press 2"))
        store.send(.save)
        await store.save()
        await eventually { (try? library.model.row("Landmine Squeeze Press 2")) != nil }
        #expect(try library.model.row("Landmine Squeeze Press 2")?.meta == "Barbell · Chest · Custom")
    }

    @Test("9 and N15. A blank, a too-short and a taken name each show their line, keep the sheet and store nothing")
    func errorsShown() async {
        let scene = CreateScene()
        let cases: [(name: String, line: String)] = [
            ("   ", "Enter a name."),
            ("A", "Name must be 2–40 characters."),
            (String(repeating: "x", count: 41), "Name must be 2–40 characters."),
            ("Row\ting", "That name holds a character that can't be saved."),
            ("barbell BENCH press", "An exercise with that name already exists.")
        ]
        for (number, item) in cases.enumerated() {
            scene.store.send(.setName(item.name))
            scene.store.send(.save)
            await scene.store.save()
            #expect(scene.store.phase == .editing, "\(item.name)")
            #expect(scene.store.model.name.problem == item.line, "\(item.name)")
            #expect(scene.store.model.foot.problem == nil)
            #expect(scene.store.attempt == number + 1)
        }
        #expect(scene.exercises.saves.isEmpty)
        scene.store.send(.setName("Barbell Bench Press Paused"))
        #expect(scene.store.model.name.problem == nil, "a change of the name forgets the line")
    }

    @Test("N15. A primary muscle is never a secondary one: choosing it takes it out, and it has no chip there")
    func primaryMuscle_isNeverSecondary() {
        let scene = CreateScene()
        scene.store.send(.setSecondaryMuscle(.triceps, isOn: true))
        scene.store.send(.setSecondaryMuscle(.chest, isOn: true))
        #expect(scene.store.draft.secondaryMuscles == [.triceps], "the primary, chest, is refused")
        scene.store.send(.setPrimaryMuscle(.triceps))
        #expect(scene.store.draft.secondaryMuscles.isEmpty)
        let secondary = scene.store.model.groups.first { $0.id == .secondaryMuscles }
        #expect(secondary?.chips.map(\.title).contains("Triceps") == false)
        #expect(secondary?.chips.count == MuscleGroup.allCases.count - 1)
        scene.store.send(.setSecondaryMuscle(.chest, isOn: true))
        scene.store.send(.setSecondaryMuscle(.chest, isOn: false))
        #expect(scene.store.draft.secondaryMuscles.isEmpty)
    }

    @Test("10 and Q5. An edit opens filled in, keeps its own name, and stores every change under the same id")
    func editCustom_storesUnderItsID() async throws {
        let custom = LibraryFixtures.custom
        let scene = CreateScene(editing: custom)
        try await scene.memory.exercises.save(custom)
        let model = scene.store.model
        #expect(model.title == "Edit exercise" && model.name.text == custom.name)
        #expect(model.groups.flatMap(\.chips).filter(\.isSelected).map(\.title) == [
            "Barbell", "Chest", "Shoulders", "Triceps", "Horizontal push"
        ])
        scene.store.send(.setEquipment(.dumbbell))
        scene.store.send(.setPattern(.verticalPush))
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .saved)
        let stored = try #require(try await scene.memory.exercises.exercise(id: custom.id))
        #expect(stored.name == custom.name && stored.equipment == .dumbbell && stored.pattern == .verticalPush)
        #expect(stored.isCustom && stored.shortName == custom.name)
    }

    @Test("10. A catalog exercise is never saved from the sheet: the save is refused and shown")
    func editCatalog_isRefused() async throws {
        let bench = try LibraryFixtures.exercise(named: "Barbell Bench Press")
        let scene = CreateScene(editing: bench)
        scene.store.send(.setName("My Bench"))
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.exercises.saves.isEmpty)
        #expect(scene.store.phase == .editing)
        #expect(scene.store.model.foot.problem == "Couldn't save the exercise. Try again.")
    }
}
