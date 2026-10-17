import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Observation

/// A launcher and its stores under test: the seeded in-memory stores (the bundled catalog, the spec's program
/// and its history), a session, and one probe that records and can hold or fail the calls made to the
/// program store and, on the host, to the host's own stores.
///
/// Two sessions: `FakeWorkoutSessionClient`, which records what it was asked and cannot fail, and the real
/// host (`LocalWorkoutSessionActor`) over the same in-memory stores behind the probe, for what the fake
/// cannot show: a discard or a start that the store refuses, and a call that is still running.
///
/// The launcher and every store are made inside `withTestDependencies`, so their dependencies are the
/// scene's for their whole life: the date fixed at `Fixtures.now`, ids counting up from 0, en_US.
@MainActor
struct WorkoutScene {
    /// Week 5 of the seed program, the week `Fixtures.seedSession()` is built for.
    nonisolated static let week = 4

    let stores: InMemoryStores
    let probe: StoreProbe
    let session: any WorkoutSessionClient
    /// The session when it is the fake, to read what it was asked.
    let fake: FakeWorkoutSessionClient?
    let launcher: WorkoutLauncher
    private let programs: ProbedProgramRepository

    /// A scene on the fake session, with `live` in progress.
    static func onFake(live: WorkoutState? = nil) throws -> WorkoutScene {
        let client = FakeWorkoutSessionClient(live: live)
        return try WorkoutScene(session: client, fake: client)
    }

    /// A scene on the real host over the probed in-memory stores, with `live` started on it.
    static func onHost(live: WorkoutState? = nil) async throws -> WorkoutScene {
        let memory = try InMemoryStores(seed: .preview())
        let probed = ProbedStores(events: memory.events, workouts: memory.workouts, programs: memory.programs)
        let host = LocalWorkoutSessionActor(
            events: probed.events,
            workouts: probed.workouts,
            programs: probed.programs,
            device: Fixtures.deviceID,
            now: { Fixtures.now }
        )
        if let live {
            try await host.start(live)
        }
        await probed.probe.clearCalls()
        return WorkoutScene(stores: memory, probed: probed, session: host, fake: nil)
    }

    /// A scene on any session, for a double of the test's own.
    static func on(_ session: any WorkoutSessionClient) throws -> WorkoutScene {
        try WorkoutScene(session: session, fake: nil)
    }

    private init(session: any WorkoutSessionClient, fake: FakeWorkoutSessionClient?) throws {
        let memory = try InMemoryStores(seed: .preview())
        let probed = ProbedStores(events: memory.events, workouts: memory.workouts, programs: memory.programs)
        self.init(stores: memory, probed: probed, session: session, fake: fake)
    }

    private init(
        stores: InMemoryStores,
        probed: ProbedStores,
        session: any WorkoutSessionClient,
        fake: FakeWorkoutSessionClient?
    ) {
        self.stores = stores
        probe = probed.probe
        programs = probed.programs
        self.session = session
        self.fake = fake
        launcher = withTestDependencies {
            Self.bind(&$0, stores: stores, programs: probed.programs, session: session)
        } operation: {
            WorkoutLauncher()
        }
    }

    private static func bind(
        _ values: inout DependencyValues,
        stores: InMemoryStores,
        programs: ProbedProgramRepository,
        session: any WorkoutSessionClient
    ) {
        values.exerciseRepository = stores.exercises
        values.programRepository = programs
        values.workoutRepository = stores.workouts
        values.workoutEventStore = stores.events
        values.settingsRepository = stores.settings
        values.statsQueries = stores.stats
        values.workoutSession = session
        values.deviceID = Fixtures.deviceID
    }

    /// A cover's store on the scene's session, as `WorkoutRoot` makes one each time the cover goes up.
    /// `configure` binds what a test wants of its own: a date that moves, a clock it steps, haptics it reads.
    func store(_ configure: (inout DependencyValues) -> Void = { _ in }) -> WorkoutStore {
        withTestDependencies {
            Self.bind(&$0, stores: stores, programs: programs, session: session)
            configure(&$0)
        } operation: {
            WorkoutStore()
        }
    }

    /// A cover's store following the session, as `WorkoutRoot`'s task makes it, once the session's first
    /// update has arrived: a workout is on screen, or the cover is closing. The task is the cover's: a test
    /// cancels it where the cover would go away.
    func following() async -> (store: WorkoutStore, task: Task<Void, Never>) {
        let store = store()
        let task = Task { await store.follow() }
        await eventually { store.shown != nil || store.exit != nil }
        return (store, task)
    }

    /// The source of the seed program's day at `index` (0 Upper A, 1 Lower A, 2 Upper B, 3 Lower B).
    static func source(day index: Int, week: Int = week) throws -> WorkoutSource {
        try WorkoutSource(
            programID: Fixtures.programID,
            weekIndex: week,
            dayTemplateID: Fixtures.seedProgram().days[index].id
        )
    }

    /// Sends the launcher what a tap sends, then runs its work as the cover modifier's task does.
    func ask(_ intent: (WorkoutLauncher) throws -> Void) async rethrows {
        try intent(launcher)
        await launcher.run()
    }

    /// The seed program with its day at `index` emptied of its slots, stored.
    func emptyDay(_ index: Int) async throws {
        var program = try Fixtures.seedProgram()
        program.days[index].slots = []
        try await stores.programs.save(program)
    }

    /// The seed program with its day at `index` deleted (`out`) or emptied, stored.
    func take(day index: Int, out isDeleted: Bool) async throws {
        if isDeleted {
            try await deleteDay(index)
        } else {
            try await emptyDay(index)
        }
    }

    /// The seed program without its day at `index`, stored.
    func deleteDay(_ index: Int) async throws {
        var program = try Fixtures.seedProgram()
        let gone = program.days.remove(at: index).id
        program.weeks = program.weeks.map { week in
            let schedule = week.schedule.filter { $0.value != gone }
            return Week(id: week.id, index: week.index, isDeload: week.isDeload, schedule: schedule)
        }
        try await stores.programs.save(program)
    }

    /// One call the fake session was asked for, by what tells it from another: a workout's state is too
    /// large a value to compare and print whole.
    enum Asked: Equatable {
        case started(WorkoutID)
        case discarded(Date)
        case finished(Date)
        case changed
    }

    /// What the fake session was asked, in order; empty on another session.
    func asked() async -> [Asked] {
        await (fake?.applied ?? []).map { event in
            switch event {
            case let .started(workout): .started(workout.id)
            case let .discarded(endedAt): .discarded(endedAt)
            case let .finished(endedAt): .finished(endedAt)
            default: .changed
            }
        }
    }

    /// Whether the session's live workout is exactly `workout`.
    func holds(_ workout: WorkoutState) async throws -> Bool {
        try await session.current() == workout
    }

    /// How many writes the host made to its event log since the scene was built or the calls were cleared.
    func appends() async -> Int {
        await probe.calls.count { $0 == .append }
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
