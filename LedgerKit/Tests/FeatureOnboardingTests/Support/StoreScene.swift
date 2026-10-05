import Dependencies
@testable import FeatureOnboarding
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// One change to the dependencies a `StoreScene` is built in.
nonisolated enum SceneChange {
    /// The injected date: another instant than `Fixtures.now`.
    case date(Date)
    case calendar(Calendar)
    /// Reading the settings throws.
    case settingsCannotBeRead
    /// Reading the catalog throws.
    case catalogCannotBeRead
    /// Reading the catalog waits at the gate, then answers.
    case catalogWaits(Gate)
    /// Saving a program throws and writes nothing.
    case programCannotBeSaved
    /// Saving a program writes it, then waits at the gate before returning.
    case saveWaitsAfterWriting(Gate)
    /// The injected logger: one a test can read back, where the default discards.
    case logger(LedgerLogger)
}

/// A store under test with what it reads and writes: in-memory stores built from a seed, and a recorder on the
/// program store that keeps every save. Built inside `withTestDependencies`, so the store's dependencies are the
/// test's for its whole life: the date fixed at `Fixtures.now` (a Wednesday), ids counting up from 0, a UTC
/// calendar and en_US.
final class StoreScene {
    let store: OnboardingStore
    let stores: InMemoryStores
    let programs: RecordingPrograms

    /// How many times a save awaited its retry preparation.
    private(set) var preparations = 0

    private init(stores: InMemoryStores, programs: RecordingPrograms) {
        store = OnboardingStore()
        self.stores = stores
        self.programs = programs
    }

    /// Runs `body` with a scene over `seed`, its dependencies changed as `changes` say.
    static func run<Result>(
        seed: InMemoryStores.Seed = .seeded(),
        changes: [SceneChange] = [],
        body: (StoreScene) async throws -> Result
    ) async throws -> Result {
        var bound: (memory: InMemoryStores, recorder: RecordingPrograms)?
        return try await withTestDependencies {
            let memory = $0.inMemoryStores(seed: seed)
            var written: any ProgramRepository = memory.programs
            var afterWrite: Gate?
            for change in changes {
                switch change {
                case let .date(date): $0.date = .constant(date)
                case let .calendar(calendar): $0.calendar = calendar
                case .settingsCannotBeRead: $0.settingsRepository = FailingSettings()
                case .catalogCannotBeRead: $0.exerciseRepository = StubbedExercises()
                case let .catalogWaits(gate):
                    $0.exerciseRepository = StubbedExercises(inner: memory.exercises, gate: gate)
                case .programCannotBeSaved: written = FailingPrograms()
                case let .saveWaitsAfterWriting(gate): afterWrite = gate
                case let .logger(logger): $0.logger = logger
                }
            }
            let recorder = RecordingPrograms(written, afterWrite: afterWrite)
            $0.programRepository = recorder
            bound = (memory, recorder)
        } operation: {
            let scene = try #require(bound.map { StoreScene(stores: $0.memory, programs: $0.recorder) })
            return try await body(scene)
        }
    }

    /// Taps "Continue" twice and "Start training", then runs the save as the root's task does.
    func startTraining() async {
        store.send(.advance)
        store.send(.advance)
        store.send(.startTraining)
        await save()
    }

    /// Runs the current attempt as the root's task does. `prepare` stands for the root's `prepareRetry`; each
    /// time the store awaits it is counted.
    func save(preparing prepare: @MainActor () async -> Void = {}) async {
        await store.save {
            preparations += 1
            await prepare()
        }
    }

    /// Seeds the bundled catalog, as the launch's seed step does when it succeeds.
    func seedCatalog() async throws {
        try await stores.exercises.seedIfNeeded(Self.catalog, version: ExerciseCatalog.version)
    }

    /// The bundled catalog; empty if it cannot be read, which `bundledCatalog_isRead` fails on.
    nonisolated static let catalog: [Exercise] = (try? ExerciseCatalog.seed()) ?? []

    /// The program a save writes for `goal` and `days`. The store's id source counts up from 0: the program
    /// takes `firstID` (0 for a store's first save) and the generator the ids after it.
    nonisolated static func expectedProgram(
        goal: TrainingGoal,
        days: DaysPerWeek,
        units: Units = .lb,
        startDate: CivilDate? = CivilDate(year: 2026, month: 9, day: 14),
        firstID: Int = 0
    ) throws -> Program {
        var next = firstID
        return try ProgramTemplates.program(
            ProgramTemplates.Request(goal: goal, days: days, units: units, startDate: #require(startDate)),
            catalog: catalog,
            id: ProgramID(UUID(firstID)),
            newID: {
                next += 1
                return UUID(next)
            }
        )
    }
}

nonisolated extension InMemoryStores.Seed {
    /// A first launch after seeding: the bundled catalog, no program, and `settings` (pounds and Monday by
    /// default).
    static func seeded(settings: Settings = .default) -> InMemoryStores.Seed {
        InMemoryStores.Seed(catalog: StoreScene.catalog, settings: settings)
    }
}
