import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// A watch store under test: the seeded in-memory stores, a session, a scripted live connection and haptics that
/// record when they played, bound inside `withTestDependencies` (the date fixed at `Fixtures.now`, the Wednesday of
/// week 5: Lower A). A `timed` scene moves the date with `clock`, which only the test moves.
@MainActor
struct WatchStoreScene {
    let stores: InMemoryStores
    let session: any WorkoutSessionClient
    let connection = FakeLiveConnection(.solo, scripted: true)
    let clock = RestCoverClock()
    let haptics: ClockedHaptics
    /// The session when it is the fake, to drive changes made elsewhere and to read what it was asked.
    let fake: FakeWorkoutSessionClient?
    /// HealthKit, when the scene runs the watch's Health session over it (F18 S3); its `events` are the session's.
    let health: FakeHealthStore?
    /// What the Health session runs over: `health`, or a stand-in in front of it (`GatedHealthStore`).
    let healthStore: (any HealthStore)?
    /// The app's display name the store is handed.
    let appName: String

    /// `seed` defaults to the previews' (`InMemoryStores.Seed.preview()`): the catalog, the seed program, its history.
    init(
        live: WorkoutState? = nil,
        session: (any WorkoutSessionClient)? = nil,
        health: FakeHealthStore? = nil,
        healthStore: (any HealthStore)? = nil,
        seed: InMemoryStores.Seed? = nil,
        appName: String = "Ledger"
    ) throws {
        stores = try InMemoryStores(seed: seed ?? .preview())
        self.appName = appName
        fake = session == nil ? FakeWorkoutSessionClient(live: live) : nil
        self.session = session ?? fake ?? FakeWorkoutSessionClient()
        self.health = health
        self.healthStore = healthStore ?? health
        haptics = ClockedHaptics(clock: clock)
    }

    /// Today's start over the scene's stores and session, at `now`.
    func today(at now: Date = Fixtures.now) -> WatchTodayStart {
        WatchTodayStart(
            session: session, programs: stores.programs, exercises: stores.exercises, stats: stores.stats,
            settings: stores.settings, device: Fixtures.deviceID, calendar: Fixtures.calendar,
            now: { now }, newID: { Fixtures.uuid(4242) }, logger: .disabled
        )
    }

    /// A store running as the root's task runs it, once the session, the program and the settings have spoken, with
    /// the watch's Health session beside it when the scene has `health`. A
    /// `timed` one sleeps on `clock`, and its date is `Fixtures.now` plus the clock's time; otherwise the date stands
    /// still and the clock's waits end at once (`withTestDependencies`).
    func running(timed: Bool = false) async -> (WatchWorkoutStore, Task<Void, Never>) {
        let healthSession = healthStore.map {
            WatchHealthSession(health: $0, workouts: session, programs: stores.programs, logger: .disabled)
        }
        let store = withTestDependencies {
            $0.exerciseRepository = stores.exercises
            $0.programRepository = stores.programs
            $0.settingsRepository = stores.settings
            $0.statsQueries = stores.stats
            $0.workoutRepository = stores.workouts
            $0.workoutSession = session
            $0.liveConnection = connection
            $0.deviceID = Fixtures.deviceID
            $0.haptics = haptics
            if timed {
                $0.continuousClock = clock
                $0.date = DateGenerator { [clock] in Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1)) }
            }
        } operation: {
            WatchWorkoutStore(appName: appName, health: healthSession)
        }
        let task = Task { [healthSession, healthStore] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await store.run() }
                if let healthSession, let healthStore {
                    group.addTask { await healthSession.run(events: healthStore.events) }
                }
            }
        }
        await observed("the store heard its sources") { store.hasHeardSession && store.idle != nil }
        return (store, task)
    }

    /// Saves the settings with the buzz at rest zero on or off, before the store runs.
    func buzz(_ isOn: Bool) async throws {
        var settings = try await stores.settings.load()
        settings.watchBuzz = isOn
        try await stores.settings.save(settings)
    }

    /// Waits until `condition`, on what the tasks asleep on `clock` do, holds (`RestCoverClock.wait(within:until:)`).
    func clockWait(_ what: String, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async {
        let outcome = await clock.wait(until: condition)
        if outcome != .held {
            Issue.record("the wait ended (\(outcome)) before: \(what)", sourceLocation: sourceLocation)
        }
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

    func publish(_ next: WorkoutState?, haptics: [Haptic] = []) {
        state = next
        readers.forEach { $0.yield(WorkoutSessionUpdate(state: next, haptics: haptics)) }
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

/// The haptics client of a store under test: what it was asked to play, and when on the scene's clock.
actor ClockedHaptics: HapticsClient {
    let clock: RestCoverClock
    private(set) var played: [Haptic] = []
    private(set) var times: [Duration] = []

    init(clock: RestCoverClock) {
        self.clock = clock
    }

    func play(_ haptic: Haptic) {
        played.append(haptic)
        times.append(clock.elapsed)
    }
}
