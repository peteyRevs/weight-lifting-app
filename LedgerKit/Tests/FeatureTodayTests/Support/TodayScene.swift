import Dependencies
@testable import FeatureToday
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Observation
import Synchronization

/// A `TodayStore` and what it reads, under test: in-memory stores seeded with the bundled catalog and the
/// re-dated seed program (`TodayFixtures.program()`: Monday 2026-09-14, so `Fixtures.now` is Lower A's day in
/// week 1), F10's fake session, and a probe on the workout store that records each read of a stretch of time
/// and can refuse it or hold it.
///
/// The store is made inside `withTestDependencies`, so its dependencies are the scene's for its whole life:
/// the clock is the scene's `clock` (at `Fixtures.now` until a test moves it), the calendar and locale are
/// `Fixtures`' unless the scene was given others.
@MainActor
struct TodayScene {
    let stores: InMemoryStores
    let workouts: ProbedWorkouts
    let fake: FakeWorkoutSessionClient
    let clock: TestNow
    let store: TodayStore

    init(
        program: Program? = nil,
        hasProgram: Bool = true,
        finished: [WorkoutState] = [],
        settings: Settings = Fixtures.settingsLb,
        live: WorkoutState? = nil,
        now: Date = Fixtures.now,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) throws {
        let seeded = try program ?? TodayFixtures.program()
        let memory = try InMemoryStores(seed: InMemoryStores.Seed(
            catalog: ExerciseCatalog.seed(),
            programs: hasProgram ? [seeded] : [],
            workouts: finished,
            settings: settings
        ))
        let probed = ProbedWorkouts(base: memory.workouts)
        let session = FakeWorkoutSessionClient(live: live)
        let time = TestNow(now)
        stores = memory
        workouts = probed
        fake = session
        clock = time
        store = withTestDependencies {
            $0.exerciseRepository = memory.exercises
            $0.programRepository = memory.programs
            $0.workoutRepository = probed
            $0.settingsRepository = memory.settings
            $0.statsQueries = memory.stats
            $0.workoutSession = session
            $0.date = DateGenerator { time.value }
            configure(&$0)
        } operation: {
            TodayStore()
        }
    }

    /// The store running, as `TodayRoot`'s task runs it, once it shows a model or a failure. The task is the
    /// root's: a test cancels it where the view would go away.
    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.model != nil || store.isFailed }
        return task
    }

    /// Lower A of week 1, the session of `Fixtures.now`, started `seconds` before it.
    static func liveLowerA(startedBefore seconds: Int = 180) throws -> WorkoutState {
        try TodayFixtures.liveWorkout(
            50,
            of: TodayFixtures.program(),
            weekIndex: 0,
            dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: Fixtures.now.addingTimeInterval(-Double(seconds))
        )
    }
}

/// The scene's clock: a moment a test can move.
final nonisolated class TestNow: Sendable {
    private let moment: Mutex<Date>

    init(_ date: Date) {
        moment = Mutex(date)
    }

    var value: Date {
        get { moment.withLock { $0 } }
        set { moment.withLock { $0 = newValue } }
    }
}

/// The in-memory workout store with its reads of a stretch of time recorded, and refused or held when a test
/// says so. Every other call goes straight through.
final nonisolated class ProbedWorkouts: WorkoutRepository {
    struct Refused: Error {}

    private struct State {
        var ranges: [Range<Date>] = []
        var observations = 0
        var isFailing = false
        var gate: ReadGate?
    }

    let base: any WorkoutRepository
    private let state = Mutex(State())

    init(base: any WorkoutRepository) {
        self.base = base
    }

    /// The stretches of time read so far, in order.
    var ranges: [Range<Date>] {
        state.withLock { $0.ranges }
    }

    /// How many times the workouts finished last were asked to be observed: once by each run of the store.
    var observations: Int {
        state.withLock { $0.observations }
    }

    /// While true, a read of a stretch of time throws `Refused`.
    var isFailing: Bool {
        get { state.withLock { $0.isFailing } }
        set { state.withLock { $0.isFailing = newValue } }
    }

    /// Makes the next reads wait at a gate, which is returned for the test to watch and open.
    func hold() -> ReadGate {
        let gate = ReadGate()
        state.withLock { $0.gate = gate }
        return gate
    }

    func workouts(in range: Range<Date>) async throws -> [WorkoutState] {
        let gate = state.withLock { state in
            state.ranges.append(range)
            return state.gate
        }
        await gate?.pass()
        if isFailing {
            throw Refused()
        }
        return try await base.workouts(in: range)
    }

    func materialize(_ workout: WorkoutState, slotUpdates: [Slot], droppingLog: Bool) async throws -> Bool {
        try await base.materialize(workout, slotUpdates: slotUpdates, droppingLog: droppingLog)
    }

    func workout(id: WorkoutID) async throws -> WorkoutState? {
        try await base.workout(id: id)
    }

    func recent(limit: Int) async throws -> [WorkoutState] {
        try await base.recent(limit: limit)
    }

    func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws {
        try await base.updateSets(workoutExerciseID: workoutExerciseID, sets: sets)
    }

    func delete(id: WorkoutID) async throws {
        try await base.delete(id: id)
    }

    func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]> {
        state.withLock { $0.observations += 1 }
        return base.observeRecent(limit: limit)
    }
}

/// Where a held read waits until the test opens it, so a test can look at the store while a read is running.
/// Both waits end when their task is cancelled, so a test whose read never comes ends at the suite's time
/// limit and fails, rather than hang. One read waits at a gate at a time, and one test watches it.
final nonisolated class ReadGate: Sendable {
    private let arrivals = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let opening = AsyncStream<Void>.makeStream()

    /// Says a read has arrived, and waits here until `open()`.
    func pass() async {
        arrivals.continuation.yield()
        for await _ in opening.stream {}
    }

    /// Returns once a read is waiting at the gate, or has passed it.
    func waitForArrival() async {
        for await _ in arrivals.stream {
            return
        }
    }

    func open() {
        opening.continuation.finish()
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

/// The `workoutSession` key's stub as Today meets it: its updates end without one, and Today calls nothing
/// else.
nonisolated struct EndedSession: WorkoutSessionClient {
    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        AsyncStream { $0.finish() }
    }

    func current() async throws -> WorkoutState? {
        throw WorkoutSessionError.noLiveWorkout
    }

    func start(_: WorkoutState) async throws {
        throw WorkoutSessionError.noLiveWorkout
    }

    func apply(_: WorkoutEvent) async throws -> WorkoutState {
        throw WorkoutSessionError.noLiveWorkout
    }

    func finish(endedAt _: Date) async throws -> WorkoutState {
        throw WorkoutSessionError.noLiveWorkout
    }

    func discard(endedAt _: Date) async throws {
        throw WorkoutSessionError.noLiveWorkout
    }
}

extension TodayStore {
    /// The model on screen, when one is.
    var model: TodayModel? {
        if case let .loaded(model) = state {
            return model
        }
        return nil
    }

    var isFailed: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    /// The state by name: a model is too large a value to compare and print whole.
    var phase: String {
        switch state {
        case .idle: "idle"
        case .loading: "loading"
        case .loaded: "loaded"
        case .failed: "failed"
        }
    }
}

/// Waits until `condition` holds, by watching what it reads (Observation), never by time. A condition that
/// never holds ends at the suite's time limit.
@MainActor
func eventually(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
    for await holds in Observations({ condition() }) where holds {
        return
    }
}
