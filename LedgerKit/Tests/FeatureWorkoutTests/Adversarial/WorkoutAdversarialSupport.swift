import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// The stores, the session and the clock one test's launcher and cover run on (G2, F10 S4).
@MainActor
struct AdversarialWorld {
    /// What answers as the session: the fake, or the real host over the in-memory stores.
    nonisolated enum Kind: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case fake, host

        var testDescription: String {
            rawValue
        }
    }

    let kind: Kind
    let stores: InMemoryStores
    /// What the launcher and the store call.
    let session: AdversarialSession
    /// The client behind `session`: asked directly, a call is "another hand" and is not counted.
    let truth: any WorkoutSessionClient
    /// The program repository as the launcher sees it: `.activeProgram` is recorded each time
    /// `StartWorkoutUseCase.start` (or the Debug sample) reads the active program.
    let launcherStores: StoreProbe
    /// The host's own stores (unused by the fake).
    let hostStores: StoreProbe
    let clock: LockIsolated<Date>
    let program: Program

    func source(day: Int, week: Int = 0) -> WorkoutSource {
        WorkoutSource(programID: program.id, weekIndex: week, dayTemplateID: program.days[day].id)
    }

    /// The live workout, asked behind the probe.
    func live() async throws -> WorkoutState? {
        try await truth.current()
    }

    /// How often `StartWorkoutUseCase.start` was entered: it reads the active program first.
    func useCaseStarts() async -> Int {
        await launcherStores.calls.count { $0 == .activeProgram }
    }

    /// Starts `day` as another hand would: through the use case, behind the probes.
    @discardableResult
    func begin(day: Int, replacingLive: Bool = false) async throws -> WorkoutState {
        let now = clock
        let useCase = StartWorkoutUseCase(
            session: truth,
            programs: stores.programs,
            exercises: stores.exercises,
            stats: stores.stats,
            settings: stores.settings,
            device: Fixtures.deviceID,
            now: { now.value },
            newID: { UUID() }
        )
        switch try await useCase.start(source(day: day), replacingLive: replacingLive) {
        case let .started(workout), let .resumed(workout), let .conflict(live: workout):
            return workout
        }
    }

    static func run(
        _ kind: Kind,
        _ body: @MainActor (AdversarialWorld) async throws -> Void
    ) async throws {
        let time = LockIsolated(Fixtures.now)
        let seed = try InMemoryStores.Seed.preview()
        let memory = InMemoryStores(seed: seed, now: { time.value })
        let host = ProbedStores(events: memory.events, workouts: memory.workouts, programs: memory.programs)
        let seen = ProbedStores(events: memory.events, workouts: memory.workouts, programs: memory.programs)
        let client: any WorkoutSessionClient = switch kind {
        case .fake:
            FakeWorkoutSessionClient()
        case .host:
            LocalWorkoutSessionActor(
                events: host.events,
                workouts: host.workouts,
                programs: host.programs,
                device: Fixtures.deviceID,
                now: { time.value }
            )
        }
        let world = try AdversarialWorld(
            kind: kind,
            stores: memory,
            session: AdversarialSession(client),
            truth: client,
            launcherStores: seen.probe,
            hostStores: host.probe,
            clock: time,
            program: #require(seed.programs.first)
        )
        try await withTestDependencies {
            $0.date = DateGenerator { time.value }
            $0.deviceID = Fixtures.deviceID
            $0.workoutSession = world.session
            $0.programRepository = seen.programs
            $0.exerciseRepository = memory.exercises
            $0.statsQueries = memory.stats
            $0.settingsRepository = memory.settings
        } operation: {
            try await body(world)
        }
    }
}

/// What the app's views do with a launcher and a cover's store, without the views (G2): it runs the
/// launcher's request as the cover modifier's task does, makes a store when the cover goes up and follows
/// the session with it, runs each discard the store asks for, and when the store says the cover is done
/// tells the launcher and keeps the route. A hosted test (`WorkoutCoverAdversarialTests`) holds the real
/// views to the same script.
@MainActor
final class AdversarialRig {
    let launcher = WorkoutLauncher()
    private(set) var store: WorkoutStore?
    private(set) var routes: [WorkoutRoute] = []
    private(set) var exits: [WorkoutExit] = []
    /// How many covers went up.
    private(set) var covers = 0
    private var following: Task<Void, Never>?
    private var discardsRun = 0

    var phase: WorkoutLaunchPhase {
        launcher.phase
    }

    /// The workout on screen: nil with the cover down, or up and not showing one.
    var shown: WorkoutState? {
        guard case let .loaded(state) = store?.workout else {
            return nil
        }
        return state
    }

    var isCoverUp: Bool {
        launcher.phase == .cover
    }

    /// Runs everything the views would run, until nothing is left to do.
    func settle() async {
        for _ in 0 ..< 50 {
            guard await step() else {
                return
            }
        }
        Issue.record("the launcher and the cover never came to rest")
    }

    /// True when it did something.
    private func step() async -> Bool {
        if launcher.phase == .working {
            await launcher.run()
            return true
        }
        guard let store else {
            guard launcher.phase == .cover else {
                return false
            }
            await open()
            return true
        }
        if launcher.phase != .cover {
            close()
            return true
        }
        if let exit = store.exit {
            exits.append(exit)
            close()
            launcher.send(.coverClosed)
            if case let .route(route) = exit {
                routes.append(route)
            }
            return true
        }
        if store.discardAttempt != discardsRun {
            discardsRun = store.discardAttempt
            await store.discard()
            await eventually("the discard to end or be refused") { store.exit != nil || !store.isDiscarding }
            return true
        }
        return false
    }

    private func open() async {
        let made = WorkoutStore()
        store = made
        covers += 1
        discardsRun = made.discardAttempt
        following = Task { await made.follow() }
        await eventually("the cover's first update") {
            if case .loaded = made.workout {
                return true
            }
            if case .failed = made.workout {
                return true
            }
            return made.exit != nil
        }
    }

    private func close() {
        following?.cancel()
        following = nil
        store = nil
    }

    /// A tap on the cover, then everything it sets off.
    func tap(_ action: WorkoutAction) async {
        store?.send(action)
        await settle()
    }

    /// An answer to one of the launcher's dialogs, then everything it sets off.
    func answer(_ action: WorkoutLaunchAction) async {
        launcher.send(action)
        await settle()
    }

    func start(_ source: WorkoutSource) async {
        launcher.start(source)
        await settle()
    }

    func resume() async {
        launcher.resume()
        await settle()
    }

    /// Waits until the cover shows what the session holds now (or has closed, when it holds nothing), then
    /// settles: for a change made by another hand.
    func absorb(_ live: WorkoutState?) async {
        if let store {
            await eventually("the cover to follow the session") {
                if let live {
                    if case let .loaded(shown) = store.workout {
                        return shown == live
                    }
                    return false
                }
                return store.exit != nil
            }
        }
        await settle()
    }
}
