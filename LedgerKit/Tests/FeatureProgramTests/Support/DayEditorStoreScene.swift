import Dependencies
@testable import FeatureProgram
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// A `DayEditorStore` and what it reads, under test (F11 S14): the scene of `ProgramStoreScene`, the spec's
/// seed program in pounds behind a `StoreProbe`, with the Day editor on one of its days (Upper A, the first,
/// by default) in week 5, the week that holds `Fixtures.now`.
///
/// The store is made inside `withTestDependencies`, so its dependencies, and its library's, are the scene's
/// for its whole life; `\.uuid` counts up from 0.
@MainActor
struct DayEditorStoreScene {
    let memory: InMemoryStores
    let probed: ProbedStores
    let program: Program
    let store: DayEditorStore

    var probe: StoreProbe {
        probed.probe
    }

    /// - Parameters:
    ///   - dayIndex: the place of the edited day among the seed program's, or nil for a day it does not hold.
    ///   - exercises: the stored exercises; the bundled catalog by default.
    init(
        dayIndex: Int? = 0,
        exercises: [Exercise]? = nil,
        configure: (inout DependencyValues, ProbedStores) -> Void = { _, _ in }
    ) throws {
        let seeded = try Fixtures.seedProgram()
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(
            catalog: exercises ?? ExerciseCatalog.seed(),
            programs: [seeded],
            workouts: [],
            settings: Fixtures.settingsLb
        ))
        let probing = ProbedStores(events: stores.events, workouts: stores.workouts, programs: stores.programs)
        let day = dayIndex.map { seeded.days[$0].id } ?? DayTemplateID(Fixtures.uuid(9090))
        memory = stores
        probed = probing
        program = seeded
        store = withTestDependencies {
            $0.exerciseRepository = stores.exercises
            $0.programRepository = probing.programs
            $0.workoutRepository = stores.workouts
            $0.settingsRepository = stores.settings
            $0.uuid = .incrementing
            configure(&$0, probing)
        } operation: {
            DayEditorStore(day: day, weekIndex: 4)
        }
    }

    /// The store running, as `DayEditorRoot`'s two tasks run it, once it shows anything but loading.
    func running() async -> ProgramStoreScene.Running {
        let running = ProgramStoreScene.Running(
            sources: Task { await store.run() },
            saving: Task { await store.save() }
        )
        await eventually { store.state != .loading }
        return running
    }

    /// Returns once no edit waits and no write runs.
    func idle() async {
        await eventually { store.session.isIdle }
    }

    /// The edited day as the store holds it now; nil when it is gone.
    func storedDay() async throws -> DayTemplate? {
        try #require(await memory.programs.active()).days.first { $0.id == store.day }
    }

    func writes() async -> Int {
        await probe.calls.count { $0 == .updateProgram }
    }

    /// The content on screen.
    var content: DayEditorModel.Content {
        get throws {
            guard case let .editing(content) = store.state else {
                throw ProgramStoreScene.NotLoaded(state: "\(store.state)")
            }
            return content
        }
    }

    /// The library sheet's model.
    var library: ExercisePickerModel {
        get throws {
            try #require(store.libraryModel)
        }
    }

    /// The id of the stored exercise of this name.
    func exercise(_ name: String) async throws -> ExerciseID {
        try #require(await memory.exercises.all().first { $0.name == name }).id
    }
}
