import Dependencies
@testable import FeatureProgram
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Observation
import Synchronization
import Testing

/// F11 S13 adversarial round 1: what the tester's store suites share, written from the slice's criteria and the
/// declarations only (no implementer test or support file was read first). The builder's store and its edit
/// session are made inside `withTestDependencies` over the in-memory stores, with the program store behind a
/// `StoreProbe` (`hold`, `hold(afterStoring:)`, `fail`) and every write and every read of the workouts written
/// to one log, in order, so a test can say what was read before what was written.
@MainActor
struct S13Rig {
    let memory: InMemoryStores
    let probed: ProbedStores
    let log: S13Log
    let ids: S13IDs
    let store: ProgramStore

    var probe: StoreProbe {
        probed.probe
    }

    var session: ProgramEditSession<ProgramBuilderEdit> {
        store.session
    }

    /// - Parameters:
    ///   - programs: the active program (the spec's seed by default), or none.
    ///   - programStore: wraps the probed program store when a test needs a store of its own (an observation
    ///     that ends, an error thrown).
    init(
        program: Program?? = .none,
        finished: [WorkoutState] = [],
        yields: Int = 0,
        now: Date = Fixtures.now,
        programStore: ((any ProgramRepository) -> any ProgramRepository)? = nil
    ) throws {
        let seeded: Program? = try program ?? Fixtures.seedProgram()
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(
            catalog: ExerciseCatalog.seed(),
            programs: seeded.map { [$0] } ?? [],
            workouts: finished,
            settings: Fixtures.settingsLb
        ))
        let calls = S13Log()
        let probes = ProbedStores(
            events: stores.events,
            workouts: stores.workouts,
            programs: stores.programs,
            yields: yields
        )
        let logged: any ProgramRepository = S13LoggedPrograms(base: probes.programs, log: calls)
        let programRepository = programStore?(logged) ?? logged
        let workoutRepository = S13LoggedWorkouts(base: stores.workouts, log: calls)
        let generator = S13IDs()
        memory = stores
        probed = probes
        log = calls
        ids = generator
        store = withTestDependencies {
            $0.programRepository = programRepository
            $0.workoutRepository = workoutRepository
            $0.exerciseRepository = stores.exercises
            $0.settingsRepository = stores.settings
            $0.date = .constant(now)
            $0.uuid = UUIDGenerator { generator.next() }
        } operation: {
            ProgramStore()
        }
    }

    /// The store's two tasks, as the root runs them: the sources and the save loop. Returns once the store
    /// shows something other than loading.
    func start() async -> (sources: Task<Void, Never>, saves: Task<Void, Never>) {
        let sources = Task { await store.run() }
        let saves = Task { await store.save() }
        await s13Until { store.state != .loading }
        return (sources, saves)
    }

    /// The program the store holds now.
    func storedProgram() async throws -> Program? {
        try await memory.programs.active()
    }

    var model: ProgramBuilderModel? {
        if case let .loaded(model) = store.state {
            return model
        }
        return nil
    }

    /// Returns once no edit waits and no write runs.
    func settled() async {
        await s13Until { store.session.isIdle }
    }

    /// The number of `update` calls the probe has seen.
    func updates() async -> Int {
        await probe.calls.filter { $0 == .updateProgram }.count
    }
}

/// A session alone, over the probed in-memory program store, fed the stored program by hand or by a follower.
@MainActor
struct S13SessionRig<Edit: ProgramEdit> {
    let memory: InMemoryStores
    let probed: ProbedStores
    let session: ProgramEditSession<Edit>

    init(
        program: Program,
        yields: Int = 0,
        programStore: ((any ProgramRepository) -> any ProgramRepository)? = nil
    ) throws {
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(
            catalog: ExerciseCatalog.seed(),
            programs: [program],
            settings: Fixtures.settingsLb
        ))
        let probes = ProbedStores(
            events: stores.events,
            workouts: stores.workouts,
            programs: stores.programs,
            yields: yields
        )
        let programRepository = programStore?(probes.programs) ?? probes.programs
        memory = stores
        probed = probes
        session = withTestDependencies {
            $0.programRepository = programRepository
        } operation: {
            ProgramEditSession<Edit>()
        }
        session.hear(program)
    }

    var probe: StoreProbe {
        probed.probe
    }

    /// Hands every program the store emits to the session, as the builder's store does.
    func follow() -> Task<Void, Never> {
        let stream = memory.programs.observeActive()
        let heard = session
        return Task { @MainActor in
            for await program in stream {
                heard.hear(program)
            }
        }
    }

    func updates() async -> Int {
        await probe.calls.filter { $0 == .updateProgram }.count
    }
}

/// Waits until `condition` holds, by watching what it reads (Observation), never by time. A condition that never
/// holds ends at the suite's time limit.
@MainActor
func s13Until(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
    for await holds in Observations({ condition() }) where holds {
        return
    }
}

/// The ids a store draws from `\.uuid`, from 70 000 on, so a reference can draw the same ones.
final nonisolated class S13IDs: Sendable {
    private let counter = Mutex(0)

    func next() -> UUID {
        counter.withLock { count in
            defer { count += 1 }
            return Fixtures.uuid(70000 + count)
        }
    }

    var drawn: Int {
        counter.withLock { $0 }
    }

    static func id(_ number: Int) -> UUID {
        Fixtures.uuid(70000 + number)
    }
}

/// What the store did, in order: `update` for each write it began, `workouts` for each read of a stretch of time.
final nonisolated class S13Log: Sendable {
    private let entries = Mutex<[String]>([])

    func append(_ entry: String) {
        entries.withLock { $0.append(entry) }
    }

    var all: [String] {
        entries.withLock { $0 }
    }

    func clear() {
        entries.withLock { $0 = [] }
    }
}

nonisolated enum S13Fixtures {
    /// A finished workout of the seed program in week `week` (0 for the first), on its first day, started at
    /// `start`, every set done.
    static func finished(week: Int, start: Date, number: Int = 1, of given: Program? = nil) throws -> WorkoutState {
        let program = try given ?? Fixtures.seedProgram()
        var built = try SessionBuilder.build(
            program: program,
            weekIndex: week,
            day: program.days[0],
            exercises: ProgramFixtures.exercises(),
            history: [:],
            settings: Fixtures.settingsLb,
            id: WorkoutID(Fixtures.uuid(0x0800_0000 + number)),
            device: Fixtures.deviceID,
            now: start
        )
        for exercise in built.exercises.indices {
            for set in built.exercises[exercise].sets.indices {
                built.exercises[exercise].sets[set].doneAt = start.addingTimeInterval(60)
            }
        }
        built.cursor = nil
        built.rest = nil
        built.endedAt = start.addingTimeInterval(3600)
        built.phase = .finished
        return built
    }

    /// 07:00 UTC on the `weekday`th day (0 Monday) of week `week` of the seed program (from Monday 2026-08-17).
    static func morning(week: Int, weekday: Int = 0) -> Date {
        Fixtures.date(2026, 8, 17, hour: 7).addingTimeInterval(Double(week * 7 + weekday) * 86400)
    }

    /// The seed program cut to `weekCount` weeks.
    static func seed(weeks weekCount: Int) throws -> Program {
        var program = try Fixtures.seedProgram()
        program.weeks = Array(program.weeks.prefix(weekCount))
        return program
    }
}

/// The edits applied one at a time, as a lifter's taps would be had each been written before the next: an edit
/// the program refuses (`removeLastWeek` at its limits) is skipped, as the screen skips it.
nonisolated func s13OneAtATime(_ edits: [ProgramBuilderEdit], to program: Program) -> Program {
    edits.reduce(program) { current, edit in
        (try? edit.applied(to: current)) ?? current
    }
}
