import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// A watch store under test: the seeded in-memory stores, a session and a scripted live connection, bound inside
/// `withTestDependencies` (the date fixed at `Fixtures.now`, the Wednesday of week 5: Lower A).
@MainActor
struct WatchStoreScene {
    let stores: InMemoryStores
    let session: any WorkoutSessionClient
    let connection = FakeLiveConnection(.solo, scripted: true)
    /// The session when it is the fake, to drive changes made elsewhere and to read what it was asked.
    let fake: FakeWorkoutSessionClient?

    init(live: WorkoutState? = nil, session: (any WorkoutSessionClient)? = nil) throws {
        stores = try InMemoryStores(seed: .preview())
        fake = session == nil ? FakeWorkoutSessionClient(live: live) : nil
        self.session = session ?? fake ?? FakeWorkoutSessionClient()
    }

    /// A store running as the root's task runs it, once the session, the program and the settings have spoken.
    func running() async -> (WatchWorkoutStore, Task<Void, Never>) {
        let store = withTestDependencies {
            $0.exerciseRepository = stores.exercises
            $0.programRepository = stores.programs
            $0.settingsRepository = stores.settings
            $0.statsQueries = stores.stats
            $0.workoutSession = session
            $0.liveConnection = connection
            $0.deviceID = Fixtures.deviceID
        } operation: {
            WatchWorkoutStore(appName: "Ledger")
        }
        let task = Task { await store.run() }
        await observed("the store heard its sources") { store.hasHeardSession && store.idle != nil }
        return (store, task)
    }

    static func settled(_ store: WatchWorkoutStore) async {
        await observed("the taps applied") { store.queue.isEmpty }
    }

    /// Day `index` as another device built it, under `id`.
    static func session(day index: Int, id: WorkoutID) throws -> WorkoutState {
        let program = try Fixtures.seedProgram()
        return try SessionBuilder.build(
            program: program, weekIndex: 4, day: program.days[index], exercises: WatchSample.catalog(),
            history: [:], settings: Fixtures.settingsLb, id: id, device: Fixtures.deviceID, now: Fixtures.now
        )
    }

    /// Lower A, today's session, with the rows of `rows` logged.
    static func lowerA(_ rows: [(Int, Int)] = [], settings: Settings = Fixtures.settingsLb) throws -> WorkoutState {
        try WatchSample.logging(rows, in: WatchSample.session(day: 1, settings: settings))
    }
}

/// Waits until `condition` holds by watching what it reads (Observation), never by time or polling, as the phone's
/// store tests do. `hangGuard` only ends a wait that would last until the suite's time limit, naming what it waited
/// for.
@MainActor
func observed(
    _ what: String,
    hangGuard: Duration = .seconds(50),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @escaping @MainActor @Sendable () -> Bool
) async {
    let watching = Task { () async -> Bool in
        for await held in Observations({ condition() }) where held {
            return true
        }
        return false
    }
    let guarding = Task {
        if await (try? Task.sleep(for: hangGuard)) != nil {
            watching.cancel()
        }
    }
    defer { guarding.cancel() }
    if await !(withTaskCancellationHandler { await watching.value } onCancel: { watching.cancel() }) {
        Issue.record("the hang guard ended the wait for: \(what)", sourceLocation: sourceLocation)
    }
}

/// A session whose stream the test writes (`publish(_:)`). Its `start` publishes `winner` instead and throws
/// `workoutInProgress`, as a start that lost to another device's does; every `apply` is refused.
actor ScriptedSession: WorkoutSessionClient {
    private var state: WorkoutState?
    private var readers: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []
    private let winner: WorkoutState?
    private(set) var starts = 0
    private(set) var applyCalls = 0

    init(winner: WorkoutState? = nil) {
        self.winner = winner
    }

    func publish(_ next: WorkoutState?) {
        state = next
        readers.forEach { $0.yield(WorkoutSessionUpdate(state: next)) }
    }

    func updates() -> AsyncStream<WorkoutSessionUpdate> {
        let (stream, reader) = AsyncStream.makeStream(of: WorkoutSessionUpdate.self)
        reader.yield(WorkoutSessionUpdate(state: state))
        readers.append(reader)
        return stream
    }

    func current() -> WorkoutState? {
        state
    }

    func start(_: WorkoutState) throws {
        starts += 1
        publish(winner)
        throw WorkoutSessionError.workoutInProgress(winner?.id ?? Fixtures.sessionID)
    }

    func apply(_: WorkoutEvent) throws -> WorkoutState {
        applyCalls += 1
        throw WorkoutSessionError.incompleteLog(Fixtures.sessionID)
    }

    func finish(endedAt _: Date) throws -> WorkoutState {
        throw WorkoutSessionError.noLiveWorkout
    }

    func discard(endedAt _: Date) throws {
        throw WorkoutSessionError.noLiveWorkout
    }
}
