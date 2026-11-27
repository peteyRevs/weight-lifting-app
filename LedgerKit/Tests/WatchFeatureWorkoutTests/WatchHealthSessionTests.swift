import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The watch's HealthKit session follows the workout (F18 S3; F16 criteria 4–6, 9, 10; F18 criteria 11, 13; spec §9).
/// Each test runs the store and the Health session as the composition runs them, over a `FakeHealthStore`, and waits
/// for what it expects by observing the store, never by time.
@MainActor
@Suite("Watch Health session", .tags(.watch), .timeLimit(.minutes(1)))
struct WatchHealthSessionTests {
    typealias Scene = WatchStoreScene
    typealias Session = FakeHealthStore.Session

    static func beat(_ bpm: Int) -> HeartRateSample {
        HeartRateSample(bpm: bpm, date: Fixtures.now)
    }

    /// A workout started from idle, with its session running.
    static func started(_ scene: Scene) async -> (WatchWorkoutStore, Task<Void, Never>) {
        let (store, task) = await scene.running()
        store.send(.start)
        await observed("set-ready, with the session running") {
            store.mode == .ready && store.healthState.running != nil && store.healthState.running == store.workout?.id
        }
        return (store, task)
    }

    @Test("Start starts the session at the workout's start; the heart rate shows; Save ends it and saves to Health")
    func start_heartRate_save() async throws {
        let health = FakeHealthStore(authorization: .authorized)
        let scene = try Scene(health: health)
        let (store, task) = await Self.started(scene)
        let id = try #require(store.workout?.id)
        #expect(await health.activeSession == Session(workoutID: id, start: Fixtures.now))
        #expect(store.health == .authorized && store.ready?.healthLine == nil)
        await health.simulateHeartRate([Self.beat(131), Self.beat(138)])
        await observed("the heart rate") { store.ready?.heartRate == "138" }
        store.send(.logSet)
        await Scene.settled(store)
        store.send(.openEnd)
        store.send(.save)
        await observed("the summary with Health's record") { store.mode == .summary && store.healthRecord != nil }
        #expect(store.summary?.averageHeartRate == "135")
        #expect(store.heartRate == nil && store.healthState.running == nil)
        let metadata = try #require(await health.savedMetadata.first)
        #expect(await health.saved.count == 1)
        #expect(await health.activeSession == nil)
        #expect(metadata.workoutID == id && metadata.doneSets == 1 && metadata.programName == "Upper / Lower")
        #expect(metadata.dayName == store.workout?.name && metadata.totalVolume.grams > 0)
        task.cancel()
    }

    @Test("Discard discards the session: nothing is written to Health")
    func discard_writesNothing() async throws {
        let health = FakeHealthStore(authorization: .authorized)
        let scene = try Scene(health: health)
        let (store, task) = await Self.started(scene)
        store.send(.openEnd)
        store.send(.discard)
        await observed("idle, with no session") { store.mode == .idle && store.healthState.running == nil }
        #expect(await health.discarded)
        #expect(await health.saved.isEmpty)
        #expect(await health.activeSession == nil)
        task.cancel()
    }

    @Test("Apple Workout takes over: logging continues, no heart rate, nothing saved; the next workout gets a session")
    func takeover_loggingContinues() async throws {
        let health = FakeHealthStore(authorization: .authorized)
        let scene = try Scene(health: health)
        let (store, task) = await Self.started(scene)
        await health.simulateHeartRate([Self.beat(120)])
        await observed("the heart rate") { store.heartRate != nil }
        await health.simulateAnotherWorkoutSessionStarted()
        await observed("the takeover") { store.isHealthTakenOver }
        #expect(store.heartRate == nil && store.ready?.heartRate == "—")
        store.send(.logSet)
        await observed("a set logged after the takeover") { store.workout?.doneSets == 1 }
        #expect(store.isHealthTakenOver && store.healthState.running == nil)
        store.send(.openEnd)
        store.send(.save)
        await observed("the summary") { store.mode == .summary }
        #expect(!store.isHealthTakenOver, "the banner is the live workout's")
        // The updates are followed in order: once the next workout's session runs, the end before it was heard.
        let next = try Scene.session(day: 0, id: WorkoutID(Fixtures.uuid(4343)))
        try await scene.fake?.start(next)
        await observed("the next workout's session") { store.healthState.running == next.id }
        #expect(await health.saved.isEmpty, "the workout taken over writes nothing to Health")
        #expect(await health.activeSession?.workoutID == next.id)
        #expect(store.healthRecord == nil)
        task.cancel()
    }

    @Test("Health denied: no session, the heart rate reads — and the line asks to allow Health")
    func denied_noSession() async throws {
        let health = FakeHealthStore(authorization: .denied)
        let scene = try Scene(live: Scene.lowerA(), health: health)
        let (store, task) = await scene.running()
        await observed("denied") { store.health == .denied }
        let ready = try #require(store.ready)
        #expect(ready.heartRate == "—" && ready.healthLine == "Allow Health in iPhone Settings")
        await health.simulateHeartRate([Self.beat(99)])
        store.send(.logSet)
        await observed("the set logged") { store.workout?.doneSets == 1 }
        #expect(await health.activeSession == nil)
        #expect(store.healthState.running == nil && store.heartRate == nil)
        task.cancel()
    }

    @Test(
        "A session the system kept is taken up, not started again, with no tap (criterion 13)",
        arguments: [true, false]
    )
    func recovery_takesTheSessionUp(byTheDelegate: Bool) async throws {
        let live = try Scene.lowerA()
        let kept = Session(workoutID: live.id, start: Fixtures.now.addingTimeInterval(-600))
        let health = FakeHealthStore(authorization: .authorized, recoverable: kept)
        if byTheDelegate {
            // `handleActiveWorkoutRecovery()` at launch, before the screen's task runs.
            #expect(try await health.recoverActiveSession())
        }
        let scene = try Scene(live: live, health: health)
        let (store, task) = await scene.running()
        await observed("set-ready with the kept session") {
            store.mode == .ready && store.healthState.running == live.id
        }
        #expect(await health.activeSession == kept, "the session is the one the system kept")
        await health.simulateHeartRate([Self.beat(101)])
        await observed("its heart rate") { store.ready?.heartRate == "101" }
        task.cancel()
    }

    @Test("A double start's winner shown in the loser's place keeps the session, and its end is the one saved")
    func winner_keepsTheSession() async throws {
        let loser = try Scene.session(day: 1, id: WorkoutID(Fixtures.uuid(4401)))
        var winner = try Scene.session(day: 1, id: WorkoutID(Fixtures.uuid(4402)))
        let session = ScriptedSession()
        await session.publish(loser)
        let health = FakeHealthStore(authorization: .authorized)
        let scene = try Scene(session: session, health: health)
        let (store, task) = await scene.running()
        await observed("the loser's session") { store.healthState.running == loser.id }
        await session.publish(winner)
        await observed("the winner's session") { store.healthState.running == winner.id }
        winner = WatchSample.logging([(0, 0)], in: winner)
        winner.phase = .finished
        winner.endedAt = Fixtures.now.addingTimeInterval(1800)
        await session.publish(winner)
        await observed("the winner saved") { store.healthRecord != nil }
        #expect(await health.savedMetadata.map(\.workoutID) == [winner.id])
        #expect(await health.saved.first?.end == winner.endedAt)
        task.cancel()
    }

    @Test("The summary counts the records the workout set against the bests before it")
    func summary_records() async throws {
        var live = try Scene.lowerA()
        live.exercises[0].sets[0].weight = .pounds(900)
        let scene = try Scene(live: live)
        let (store, task) = await scene.running()
        store.send(.logSet)
        await Scene.settled(store)
        store.send(.openEnd)
        store.send(.save)
        await observed("the summary's records") { store.summary?.hasRecords == true }
        #expect(store.records.allSatisfy { $0.exerciseID == live.exercises[0].exerciseID })
        task.cancel()
    }
}

/// The watch's own start (F17 criterion 8, F18 criterion 13): today's day, with no tap.
extension WatchHealthSessionTests {
    @Test("The watch's own start begins today's day: set-ready and its session, with no tap")
    func ownStart_todaysDay() async throws {
        let health = FakeHealthStore(authorization: .authorized)
        let scene = try Scene(health: health)
        let (store, task) = await scene.running()
        #expect(store.mode == .idle)
        await scene.today().startOwnWorkout()
        await observed("set-ready with its session") {
            store.mode == .ready && store.healthState.running == store.workout?.id
        }
        let program = try Fixtures.seedProgram()
        #expect(store.workout?.source?.dayTemplateID == program.days[1].id, "Wednesday of week 5 is Lower A")
        #expect(await health.activeSession?.workoutID == WorkoutID(Fixtures.uuid(4242)))
        // Asked again with the day live, it resumes the day and starts nothing.
        guard case .resumed? = try await scene.today().start() else {
            Issue.record("today's live day was not resumed")
            task.cancel()
            return
        }
        task.cancel()
    }

    @Test("With no program, or on a rest day, the watch's own start starts nothing")
    func ownStart_nothingToStart() async throws {
        let thursday = Fixtures.now.addingTimeInterval(86400)
        let scene = try Scene()
        #expect(try await scene.today(at: thursday).start() == nil, "Thursday is a rest day")
        try await scene.stores.programs.delete(Fixtures.programID)
        await scene.today().startOwnWorkout()
        #expect(try await scene.today().start() == nil, "no program")
        #expect(try await scene.session.current() == nil)
    }
}
