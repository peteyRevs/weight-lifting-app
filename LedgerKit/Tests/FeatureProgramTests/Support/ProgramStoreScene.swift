import Dependencies
@testable import FeatureProgram
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Observation
import Synchronization
import Testing

/// A `ProgramStore` and what it reads, under test (F11 S13): in-memory stores seeded with the bundled catalog,
/// the spec's seed program (it began on 2026-08-17, so `Fixtures.now` is in its week 5) and the settings in
/// pounds; the program store behind a `StoreProbe` that can hold, fail and count its updates.
///
/// The store is made inside `withTestDependencies`, so its dependencies are the scene's for its whole life.
@MainActor
struct ProgramStoreScene {
    let memory: InMemoryStores
    let probed: ProbedStores
    let store: ProgramStore

    var probe: StoreProbe {
        probed.probe
    }

    init(
        program: Program? = nil,
        hasProgram: Bool = true,
        finished: [WorkoutState] = [],
        configure: (inout DependencyValues, ProbedStores) -> Void = { _, _ in }
    ) throws {
        let seeded = try program ?? Fixtures.seedProgram()
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(
            catalog: ExerciseCatalog.seed(),
            programs: hasProgram ? [seeded] : [],
            workouts: finished,
            settings: Fixtures.settingsLb
        ))
        let probing = ProbedStores(events: stores.events, workouts: stores.workouts, programs: stores.programs)
        memory = stores
        probed = probing
        store = withTestDependencies {
            $0.exerciseRepository = stores.exercises
            $0.programRepository = probing.programs
            $0.workoutRepository = stores.workouts
            $0.settingsRepository = stores.settings
            configure(&$0, probing)
        } operation: {
            ProgramStore()
        }
    }

    /// The store running, as `ProgramRoot`'s two tasks run it, once it shows anything but loading. The tasks
    /// are the root's: a test cancels them where the view would go away.
    func running() async -> Running {
        let running = Running(sources: Task { await store.run() }, saving: Task { await store.save() })
        await eventually { store.state != .loading }
        return running
    }

    /// Returns once no edit waits and no write runs.
    func idle() async {
        await eventually { store.session.isIdle }
    }

    /// The program as the store holds it now.
    func stored() async throws -> Program {
        try #require(await memory.programs.active())
    }

    /// The writes the store made so far.
    func writes() async -> Int {
        await probe.calls.count { $0 == .updateProgram }
    }

    /// The model on screen.
    var model: ProgramBuilderModel {
        get throws {
            guard case let .loaded(model) = store.state else {
                throw NotLoaded(state: "\(store.state)")
            }
            return model
        }
    }

    struct NotLoaded: Error {
        let state: String
    }

    /// The two tasks of a running store.
    struct Running {
        let sources: Task<Void, Never>
        let saving: Task<Void, Never>

        func cancel() async {
            sources.cancel()
            saving.cancel()
            await sources.value
            await saving.value
        }
    }
}

/// A finished workout of `program`'s week `weekIndex` (0 for the first), for a test to store: one of
/// `Fixtures`' history of the seed program, newest first (`number` picks which, each with its own id; all
/// started in the seed block), said to come from that week.
func finishedWorkout(of program: Program, weekIndex: Int, number: Int = 0) throws -> WorkoutState {
    let history = try Array(Fixtures.history(weeks: 4).reversed())
    var workout = try #require(history.indices.contains(number) ? history[number] : nil)
    workout.source = try WorkoutSource(
        programID: program.id,
        weekIndex: weekIndex,
        dayTemplateID: #require(workout.source).dayTemplateID
    )
    return workout
}

/// Waits until `condition` holds, by watching what it reads (Observation), never by time. A condition that
/// never holds ends at the suite's time limit.
@MainActor
func eventually(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
    for await holds in Observations({ condition() }) where holds {
        return
    }
}

/// A program store whose observation ends at once, as a database observation does when its read fails.
nonisolated struct EndedPrograms: ProgramRepository {
    struct Unused: Error {}

    func observeActive() -> AsyncStream<Program?> {
        AsyncStream { $0.finish() }
    }

    func active() async throws -> Program? {
        throw Unused()
    }

    func save(_: Program) async throws {
        throw Unused()
    }

    func update(_: ProgramID, _: @Sendable (Program) throws -> Program) async throws -> Program {
        throw Unused()
    }

    func setActive(_: ProgramID) async throws {
        throw Unused()
    }

    func delete(_: ProgramID) async throws {
        throw Unused()
    }
}

/// A program store whose next update cancels its own task from inside its change, with `TaskCancelSwitch`
/// (F11 S3): the cancellation lands after the read and before anything is stored, at no time a clock picks.
final nonisolated class CancellingPrograms: ProgramRepository {
    private let base: any ProgramRepository
    let cancel = TaskCancelSwitch()
    private let armed = Mutex(true)

    init(base: any ProgramRepository) {
        self.base = base
    }

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        let fires = armed.withLock { armed in
            defer { armed = false }
            return armed
        }
        let cancelling = cancel
        return try await base.update(id) { program in
            if fires {
                cancelling.fire()
            }
            return try change(program)
        }
    }

    func observeActive() -> AsyncStream<Program?> {
        base.observeActive()
    }

    func active() async throws -> Program? {
        try await base.active()
    }

    func save(_ program: Program) async throws {
        try await base.save(program)
    }

    func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }
}

extension ProgramStore.State {
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}
