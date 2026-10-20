import Dependencies
@testable import FeatureProgram
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S14 adversarial round 1: the Day editor's store and the library's, written from the slice's criteria
/// (15 to 19), Pete's questions built to A, rulings R1, R5 and R6, and the declarations. The builder's store and
/// the Day editor's run side by side over one probed program store, as the Program tab holds them: the builder
/// under the pushed editor. Each wait is on what a store shows (Observation), never on time.
@MainActor
@Suite("Adversarial F11 S14 · the Day editor's and the library's stores", .tags(.feature), .timeLimit(.minutes(1)))
struct DayEditorStoreAdversarialTests {
    private static func stop(_ tasks: [Task<Void, Never>]) async {
        for task in tasks {
            task.cancel()
        }
        for task in tasks {
            await task.value
        }
    }

    // MARK: The builder and the Day editor on one program

    @Test("Builder and Day editor edits interleaved around a held write: both kept, and both screens are the store")
    func builderAndEditor_interleavedDuringAHeldWrite_bothScreensEndAsStored() async throws {
        let both = try S14Both()
        let builderTasks = await both.runBuilder()
        let editorTasks = await both.runEditor()
        await both.probe.hold(.updateProgram)
        both.builder.send(.rename("Upper Lower"))
        try await both.probe.waitUntilHeld()
        // While the builder's write is held, the Day editor renames its day and steps a field: its own write
        // reaches the store before the builder's is let go.
        both.editor.send(.rename("Push", day: both.editor.day))
        try both.editor.send(both.content.row("1").action)
        try both.editor.send(#require(both.content.openRow?.panel?.details).field("SETS").increment)
        await s13Until { both.editor.session.isIdle }
        await both.probe.release()
        await s13Until { both.builder.session.isIdle }
        let stored = try await both.stored()
        #expect(stored.name == "Upper Lower")
        #expect(stored.days[0].name == "Push")
        #expect(stored.days[0].slots[0].sets == both.program.days[0].slots[0].sets + 1)
        await s13Until { both.builder.session.shown == stored && both.editor.session.shown == stored }
        let builderMatches = both.builder.session.shown == stored
        let editorMatches = both.editor.session.shown == stored
        #expect(builderMatches && editorMatches)
        await Self.stop(builderTasks + editorTasks)
    }

    // MARK: Closing (criteria 16 and 17)

    @Test("17. \"Done\", an edit behind it, and that second write fails: no close, the alert, the screen is the store")
    func done_thenTheSecondWriteFails_dropsTheClose_andShowsWhatIsStored() async throws {
        let both = try S14Both()
        let tasks = await both.runEditor()
        await both.probe.hold(.updateProgram, afterStoring: true)
        both.editor.send(.rename("Push", day: both.editor.day))
        try await both.probe.waitUntilHeld()
        try both.editor.send(both.content.header.done.action)
        both.editor.send(.rename("Push A", day: both.editor.day))
        // The first write has stored "Push" and is held; the next call is refused before the store.
        await both.probe.fail(.updateProgram)
        await both.probe.release()
        await s13Until { both.editor.session.isIdle && both.editor.showsSaveFailure }
        #expect(both.editor.pendingRoute == nil, "a failed write drops the close (question 1, A)")
        #expect(try await both.storedDay()?.name == "Push")
        #expect(try both.content.header.name == "Push", "the screen is the day as stored")
        both.editor.showsSaveFailure = false
        try both.editor.send(both.content.header.done.action)
        #expect(both.editor.pendingRoute?.route == .closeDay)
        await Self.stop(tasks)
    }

    @Test("17 and R1. \"Done\" during a cancelled write: the edit is sent on the next run, then it closes")
    func done_writeCancelled_closesAfterTheNextRunStoresIt() async throws {
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
        scene.store.send(.rename("Push", day: scene.store.day))
        try scene.store.send(scene.content.header.done.action)
        _ = await saving.result
        #expect(scene.store.pendingRoute == nil, "nothing is stored yet, so nothing closes")
        #expect(!scene.store.showsSaveFailure)
        #expect(try scene.content.header.name == "Push", "the edit is kept on screen (R1)")
        let again = Task { await scene.store.save() }
        await eventually { scene.store.pendingRoute != nil }
        #expect(scene.store.pendingRoute?.route == .closeDay)
        #expect(try await scene.storedDay()?.name == "Push")
        again.cancel()
        sources.cancel()
        await again.value
        await sources.value
    }

    @Test("16. The day deleted elsewhere while the editor's own write on it is held: one close, no alert, nothing back")
    func dayDeletedElsewhere_duringTheEditorsHeldWrite_closesOnce_andDoesNotBringItBack() async throws {
        let both = try S14Both()
        let tasks = await both.runEditor()
        await both.probe.hold(.updateProgram)
        try both.editor.send(both.content.row("1").action)
        try both.editor.send(#require(both.content.openRow?.panel?.details).field("SETS").increment)
        try await both.probe.waitUntilHeld()
        let day = both.editor.day
        _ = try await both.memory.programs.update(both.program.id) { ProgramEditing.deleteDay($0, day: day) }
        await both.probe.release()
        await s13Until { both.editor.pendingRoute != nil }
        var handed: [ProgramRoute] = []
        both.editor.deliverRoute { handed.append($0) }
        both.editor.deliverRoute { handed.append($0) }
        #expect(handed == [.closeDay])
        #expect(both.editor.state == .dayIsGone)
        #expect(!both.editor.showsSaveFailure)
        #expect(try await both.storedDay() == nil, "the editor's write does not bring the day back")
        await Self.stop(tasks)
    }

    @Test("16 and 17. The day deleted elsewhere and the editor's write fails: it closes, the alert set as it goes")
    func dayDeletedElsewhere_andTheWriteFails_closesWithTheAlertSet() async throws {
        let both = try S14Both()
        let tasks = await both.runEditor()
        await both.probe.hold(.updateProgram)
        try both.editor.send(both.content.row("1").action)
        try both.editor.send(#require(both.content.openRow?.panel?.details).field("SETS").increment)
        try await both.probe.waitUntilHeld()
        let day = both.editor.day
        _ = try await both.memory.programs.update(both.program.id) { ProgramEditing.deleteDay($0, day: day) }
        await both.probe.fail(.updateProgram)
        await both.probe.release()
        await s13Until { both.editor.pendingRoute != nil }
        // Pinned as built (note F11-S14-4): the day is gone, so the editor closes although a write failed; the
        // alert is asked for on a screen that is being popped.
        #expect(both.editor.pendingRoute?.route == .closeDay)
        #expect(both.editor.showsSaveFailure)
        #expect(both.editor.state == .dayIsGone)
        await Self.stop(tasks)
    }

    @Test("16. \"Delete\" while another of the editor's writes is held: both stored in order, then one close")
    func delete_behindAHeldWrite_closesOnceBothAreStored() async throws {
        let both = try S14Both()
        let tasks = await both.runEditor()
        await both.probe.hold(.updateProgram)
        both.editor.send(.rename("Push", day: both.editor.day))
        try await both.probe.waitUntilHeld()
        try both.editor.send(both.content.deleteDay.confirmation.confirm.action)
        #expect(both.editor.state == .dayIsGone)
        #expect(both.editor.pendingRoute == nil, "the delete waits behind the held write")
        await both.probe.release()
        await s13Until { both.editor.pendingRoute != nil }
        #expect(both.editor.pendingRoute?.route == .closeDay)
        #expect(try await both.storedDay() == nil)
        #expect(await both.writes() == 2)
        await Self.stop(tasks)
    }
}

/// The library sheet during the editor's writes (criterion 19, question 4).
extension DayEditorStoreAdversarialTests {
    @Test("19. Two \"Add\"s while a write is held: each exercise once, in order, marked in the day while it waits")
    func library_twoAddsWhileAWriteIsHeld_storeEachOnceInOrder() async throws {
        let both = try S14Both()
        let tasks = await both.runEditor()
        let before = both.program.days[0].slots.count
        await both.probe.hold(.updateProgram)
        both.editor.send(.rename("Push", day: both.editor.day))
        try await both.probe.waitUntilHeld()
        let squat = try await both.exercise("Back Squat")
        let front = try await both.exercise("Front Squat")
        let curl = try await both.exercise("Barbell Curl")
        both.editor.send(.openLibrary)
        both.editor.send(ExercisePickerAction.setMuscle(.legs))
        both.editor.send(ExercisePickerAction.setPicked(true, exercise: squat))
        both.editor.send(ExercisePickerAction.setPicked(true, exercise: front))
        both.editor.send(ExercisePickerAction.add([squat, front]))
        both.editor.send(.openLibrary)
        let library = try #require(both.editor.libraryModel)
        #expect(library.muscles.chips.contains { $0.isSelected && $0.title == "Legs" }, "the chip is kept")
        let marked = library.rows.filter { $0.line.hasSuffix("already in this day") }.map(\.id)
        #expect(marked.contains(squat) && marked.contains(front), "waiting slots are already in this day")
        both.editor.send(ExercisePickerAction.setPicked(true, exercise: curl))
        both.editor.send(ExercisePickerAction.add([curl]))
        #expect(try both.content.rows.suffix(3).map(\.name) == ["Back Squat", "Front Squat", "Barbell Curl"])
        await both.probe.release()
        await s13Until { both.editor.session.isIdle }
        let day = try #require(try await both.storedDay())
        #expect(day.slots.count == before + 3)
        #expect(day.slots.suffix(3).map(\.exerciseID) == [squat, front, curl])
        #expect(Set(day.slots.map(\.id)).count == day.slots.count, "every new slot has an id of its own")
        #expect(await both.writes() == 2, "the rename, then both adds together")
        await Self.stop(tasks)
    }

    @Test("19. \"Add\" with nothing that can be added writes nothing and still closes the sheet")
    func library_addOfOnlyStrangers_writesNothing() async throws {
        let both = try S14Both()
        let tasks = await both.runEditor()
        both.editor.send(.openLibrary)
        both.editor.send(ExercisePickerAction.add([ExerciseID(Fixtures.uuid(4242))]))
        #expect(!both.editor.library.isShown)
        await s13Until { both.editor.session.isIdle }
        #expect(await both.writes() == 0)
        await Self.stop(tasks)
    }
}

/// The builder's store and the Day editor's store on the seed program's first day, both made over the same
/// probed in-memory stores.
@MainActor
struct S14Both {
    let memory: InMemoryStores
    let probed: ProbedStores
    let program: Program
    let builder: ProgramStore
    let editor: DayEditorStore

    var probe: StoreProbe {
        probed.probe
    }

    init(dayIndex: Int = 0) throws {
        let seeded = try Fixtures.seedProgram()
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(
            catalog: ExerciseCatalog.seed(),
            programs: [seeded],
            workouts: [],
            settings: Fixtures.settingsLb
        ))
        let probing = ProbedStores(events: stores.events, workouts: stores.workouts, programs: stores.programs)
        let ids = S13IDs()
        memory = stores
        probed = probing
        program = seeded
        (builder, editor) = withTestDependencies {
            $0.exerciseRepository = stores.exercises
            $0.programRepository = probing.programs
            $0.workoutRepository = stores.workouts
            $0.settingsRepository = stores.settings
            $0.date = .constant(Fixtures.now)
            $0.uuid = UUIDGenerator { ids.next() }
        } operation: {
            (ProgramStore(), DayEditorStore(day: seeded.days[dayIndex].id, weekIndex: 4))
        }
    }

    func runEditor() async -> [Task<Void, Never>] {
        let tasks = [Task { await editor.run() }, Task { await editor.save() }]
        await s13Until { editor.state != .loading }
        return tasks
    }

    func runBuilder() async -> [Task<Void, Never>] {
        let tasks = [Task { await builder.run() }, Task { await builder.save() }]
        await s13Until { builder.state != .loading }
        return tasks
    }

    var content: DayEditorModel.Content {
        get throws {
            guard case let .editing(content) = editor.state else {
                throw ProgramStoreScene.NotLoaded(state: "\(editor.state)")
            }
            return content
        }
    }

    func stored() async throws -> Program {
        try #require(try await memory.programs.active())
    }

    func storedDay() async throws -> DayTemplate? {
        try await stored().days.first { $0.id == editor.day }
    }

    func exercise(_ name: String) async throws -> ExerciseID {
        try #require(await memory.exercises.all().first { $0.name == name }).id
    }

    func writes() async -> Int {
        await probe.calls.count { $0 == .updateProgram }
    }
}
