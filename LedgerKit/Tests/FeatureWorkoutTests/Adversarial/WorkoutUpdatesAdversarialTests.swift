import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// G2, F10 S4 criterion 7, rows L25 and L26: what the cover's store does with a stream no well-behaved
/// client writes on one phone. The stream is written by hand (`ScriptedSession`).
@MainActor
@Suite("Workout updates (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutUpdatesAdversarialTests {
    private func workout(_ number: Int) -> WorkoutState {
        EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(EventBuilders.uuid(0xAA00 + number)))
    }

    /// A store following `session`, and its task.
    private func following(_ session: ScriptedSession) async -> (WorkoutStore, Task<Void, Never>) {
        let store = withTestDependencies {
            $0.workoutSession = session
        } operation: {
            WorkoutStore()
        }
        let task = Task { await store.follow() }
        await eventually("the store to subscribe") { store.onScreen != nil || store.exit != nil }
        return (store, task)
    }

    @Test("Nothing live when the cover opens: it closes with nothing to tell")
    func firstUpdate_nothingLive_closesWithoutARoute() async {
        let (store, task) = await following(ScriptedSession(live: nil))
        defer { task.cancel() }
        #expect(store.exit == .nothingToShow)
        #expect(store.onScreen == nil)
    }

    @Test("L25: a stream that ends leaves no workout on screen that no longer follows; the way out works")
    func streamEnds_isShownAsFailed_andCloses() async {
        let session = ScriptedSession(live: workout(1))
        let (store, task) = await following(session)
        await session.endStreams()
        await task.value
        guard case .failed = store.model else {
            Issue
                .record(
                    "the stream ended and the cover still draws \(store.onScreen == nil ? "nothing" : "the workout")"
                )
            return
        }
        #expect(store.exit == nil)
        store.send(.finish)
        store.send(.discard)
        await store.discard()
        #expect(store.dialog == nil)
        #expect(await session.discards == 0)
        store.send(.minimize)
        #expect(store.exit != nil, "the failed screen's Close closes the cover")
    }

    @Test("L26: an update for another workout shows that workout, never the first as if it were live")
    func otherWorkoutsUpdate_isWhatTheCoverShows() async {
        let session = ScriptedSession(live: workout(1))
        let (store, task) = await following(session)
        defer { task.cancel() }
        let other = workout(2)
        await session.publish(other)
        await eventually("the second workout") { store.onScreen?.id == other.id }
        #expect(store.exit == nil)
    }

    @Test("An ending update closes the cover once; what the stream says afterwards changes nothing")
    func afterTheEnd_laterUpdatesChangeNothing() async {
        let first = workout(1)
        let session = ScriptedSession(live: first)
        let (store, task) = await following(session)
        defer { task.cancel() }
        var ended = first
        ended.phase = .discarded
        await session.publish(ended)
        await eventually("the cover to close") { store.exit != nil }
        #expect(store.exit == .route(.discarded))
        var finished = workout(2)
        finished.phase = .finished
        await session.publish(workout(2))
        await session.publish(finished)
        await giveWay()
        #expect(store.exit == .route(.discarded), "the exit is set once")
    }

    @Test("A finished update closes as saved with the workout's id")
    func finishedUpdate_closesAsSaved() async {
        let first = workout(1)
        let session = ScriptedSession(live: first)
        let (store, task) = await following(session)
        defer { task.cancel() }
        var finished = first
        finished.phase = .finished
        finished.endedAt = first.startedAt.addingTimeInterval(60)
        await session.publish(finished)
        await eventually("the cover to close") { store.exit != nil }
        #expect(store.exit == .route(.saved(first.id)))
    }

    @Test("Many updates at once: the cover ends on the last one")
    func burstOfUpdates_endsOnTheLast() async {
        var state = workout(1)
        let session = ScriptedSession(live: state)
        let (store, task) = await following(session)
        defer { task.cancel() }
        for index in 0 ..< 500 {
            state.name = "Update \(index)"
            await session.publish(state)
        }
        await eventually("the last update") { store.onScreen?.name == "Update 499" }
        #expect(store.model.drawnHeader?.title == "Update 499")
    }
}

/// G2, F10 S4 criterion 2: "after the app is killed and relaunched with a live workout, the launcher can
/// show it". A relaunch here is a new host over the stores the first one wrote, and a new launcher.
@MainActor
@Suite("Workout after a relaunch (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutRelaunchAdversarialTests {
    private let stores: InMemoryStores
    private let program: Program
    private let clock = LockIsolated(Fixtures.now)

    init() throws {
        let seed = try InMemoryStores.Seed.preview()
        stores = InMemoryStores(seed: seed)
        program = try #require(seed.programs.first)
    }

    /// What one process does with its launcher and its host.
    typealias Process = @MainActor (AdversarialRig, any WorkoutSessionClient) async throws -> Void

    private func source(_ day: Int) -> WorkoutSource {
        WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: program.days[day].id)
    }

    /// One process: a new host over the same stores, and a launcher made on it.
    private func launch(_ body: Process) async throws {
        let (memory, time) = (stores, clock)
        let host = LocalWorkoutSessionActor(
            events: memory.events,
            workouts: memory.workouts,
            programs: memory.programs,
            device: Fixtures.deviceID,
            now: { time.value }
        )
        try await withTestDependencies {
            $0.date = DateGenerator { time.value }
            // Each launch would otherwise count its ids from zero again, and name two workouts alike.
            $0.uuid = UUIDGenerator { UUID() }
            $0.deviceID = Fixtures.deviceID
            $0.workoutSession = host
            $0.programRepository = memory.programs
            $0.exerciseRepository = memory.exercises
            $0.statsQueries = memory.stats
            $0.settingsRepository = memory.settings
        } operation: {
            try await body(AdversarialRig(), host)
        }
    }

    @Test("After a relaunch the live workout is shown by resume and by its day, and another day asks")
    func relaunch_liveWorkout_isShownAndGuarded() async throws {
        var first: WorkoutID?
        try await launch { rig, host in
            await rig.start(source(0))
            first = try await host.current()?.id
            #expect(rig.phase == .cover)
        }
        // Killed: nothing of the first process is kept. Twenty-four minutes later:
        clock.setValue(Fixtures.now.addingTimeInterval(1462))
        try await launch { rig, host in
            await rig.resume()
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == first)
            #expect(rig.shown?.startedAt == Fixtures.now, "the elapsed time counts from the workout's start")
            await rig.tap(.minimize)
            await rig.start(source(0))
            #expect(rig.shown?.id == first)
            await rig.tap(.minimize)
            await rig.start(source(1))
            #expect(rig.phase == .conflict(source(1)))
            await rig.answer(.replaceLive(source(1)))
            let live = try await host.current()
            #expect(live?.source == source(1))
            #expect(rig.shown?.id == live?.id)
        }
        try await launch { rig, _ in
            await rig.resume()
            #expect(rig.shown?.source == source(1), "after a second relaunch the replacement is the live one")
            #expect(rig.shown?.id != first)
        }
    }
}
