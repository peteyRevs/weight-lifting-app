import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, criterion 18: the cover's tasks starting again while a save runs. A cancelled save shows
/// nothing; the task that starts again runs the same save, with the same end; and every outcome closes
/// the cover onto the saved workout, which history holds once. The real host holds a save in its store;
/// a double of the test target completes one whose caller was cancelled, as a host does.
@MainActor
@Suite("WorkoutStore save across a restart", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSaveRestartTests {
    typealias Failure = WorkoutStoreSaveFailureTests
    typealias Pump = WorkoutStorePumpTests
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    // MARK: Criterion 18: the cover's tasks starting again

    @Test("A save cancelled with the cover's tasks shows nothing; the task that starts again runs the same save")
    func save_cancelledAndStartedAgain_savesOnce() async throws {
        let running = try Save.logged(2)
        let date = LockIsolated(Fixtures.now.addingTimeInterval(300))
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Failure.saving(scene, at: date)
        await scene.probe.hold(.materialize)
        let work = Task { await store.save() }
        try await scene.probe.waitUntilHeld()
        work.cancel()
        task.cancel()
        date.withValue { $0 += 60 }
        // The cover's tasks start again while the host is still saving.
        let again = Task { await store.follow() }
        let next = Task { await store.save() }
        await scene.probe.release()
        await work.value
        await next.value
        await again.value

        #expect(store.dialog != .saveFailed)
        #expect(store.doneOnReceipt(of: running.id), "F10 S7b: the receipt shows first; Done closes the cover")
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.saveAttempt == 1)
        let stored = try #require(try await scene.stores.workouts.workout(id: running.id))
        #expect(stored.endedAt == Fixtures.now.addingTimeInterval(300), "the same end as the first run")
        #expect(await Failure.materializes(scene) == 1, "history holds the workout once")
    }

    @Test("A save whose answer never reached the store: the next stream has no workout, and the cover closes as saved")
    func save_answerLost_closesAsSaved() async throws {
        let running = try Save.logged(1)
        let gate = Gate()
        let scene = try Scene.on(HeldFinishSession(base: FakeWorkoutSessionClient(live: running), gate: gate))
        let (store, task) = await scene.following()
        store.send(.save)
        let work = Task { await store.save() }
        await gate.waitForArrival()
        // The cover's tasks end; the session completes the save in its own time.
        work.cancel()
        task.cancel()
        await task.value
        await gate.open()
        await work.value
        #expect(store.exit == nil, "the cancelled call told the store nothing")
        #expect(store.dialog == .finish)
        #expect(store.isSaving)

        // They start again: the stream's first update says that nothing is live.
        await store.save()
        await store.follow()
        #expect(store.exit == .route(.saved(running.id)), "never nothingToShow, never the failure alert")
        #expect(store.saved == nil, "F10 S7b, product default O7: no finished state reached the store, no receipt")
        #expect(store.dialog == nil)
    }

    @Test("A cover that opens on no workout, with no save of its own, still has nothing to show")
    func noWorkout_withoutASave_isNothingToShow() async throws {
        let scene = try Scene.onFake()
        let store = scene.store()
        store.send(.save)
        await store.save()
        await store.follow()
        #expect(store.exit == .nothingToShow)
    }

    @Test("Tasks start again while the save waits for a tap: the tap is planned on the session's workout, then saved")
    func restartWhileTheSaveWaits_followsTheTaps() async throws {
        let running = try Save.logged(1)
        let bench = Pump.sets(0, of: running)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        task.cancel()
        await task.value
        // Not hearing the session: the tap and the save wait.
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[1])))
        store.send(.save)
        let stalled = Task { await store.save() }
        await giveWay()
        #expect(await scene.asked() == [], "nothing is planned on a workout the store is not hearing")
        stalled.cancel()
        await stalled.value
        #expect(store.isSaving)

        // Meanwhile the set was logged elsewhere; the tasks start again.
        let set = running.exercises[0].sets[1]
        try await scene.fake?.apply(.setLogged(
            exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: Fixtures.now
        ))
        let again = Task { await store.follow() }
        await store.save()
        #expect(await scene.asked() == [.changed, .finished(Fixtures.now)], "the waiting log found the set logged")
        #expect(store.doneOnReceipt(of: running.id), "F10 S7b: the receipt shows first; Done closes the cover")
        #expect(store.exit == .route(.saved(running.id)))
        await again.value
    }
}
