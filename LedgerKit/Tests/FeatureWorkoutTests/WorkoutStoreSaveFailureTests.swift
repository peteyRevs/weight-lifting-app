import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, criteria 15 to 17 and 19: a save that does not go through is shown and loses nothing; "Try
/// again" and "Close"; a workout that ended by another hand first. The real host over probed stores
/// refuses a save; the fake and a double of the test target stand for a session that answers otherwise.
/// The cover's tasks starting again while a save runs are `WorkoutStoreSaveRestartTests`'.
@MainActor
@Suite("WorkoutStore save failures", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSaveFailureTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    /// A store on the host with "Save workout" tapped at `date`'s moment, and its follow.
    static func saving(
        _ scene: Scene,
        at date: LockIsolated<Date> = LockIsolated(Fixtures.now)
    ) async -> (store: WorkoutStore, task: Task<Void, Never>) {
        let store = scene.store(Save.moving(date))
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        store.send(.finish)
        store.send(.save)
        return (store, task)
    }

    static func materializes(_ scene: Scene) async -> Int {
        await scene.probe.calls.count { $0 == .materialize }
    }

    // MARK: Criteria 15 and 16

    @Test("A save the store refuses is shown; the workout stays; Try again saves it, ended at the first tap")
    func save_refused_isShown_tryAgainSaves() async throws {
        let running = try Save.logged(2)
        let date = LockIsolated(Fixtures.now.addingTimeInterval(900))
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Self.saving(scene, at: date)
        await scene.probe.fail(.materialize)
        await store.save()

        #expect(store.dialog == .saveFailed, "the sheet is down and the alert is up")
        #expect(!store.isSaving)
        #expect(store.exit == nil)
        #expect(store.shown?.id == running.id)
        #expect(store.model.header?.isEnabled == true)
        #expect(try await scene.stores.workouts.workout(id: running.id) == nil, "nothing reached history")
        #expect(try await scene.session.current()?.phase == .live)

        // The clock has moved on before "Try again".
        date.withValue { $0 += 120 }
        store.send(.retrySave)
        #expect(store.dialog == nil)
        #expect(store.isSaving)
        #expect(store.saveAttempt == 2)
        #expect(store.model.header?.isEnabled == false)
        await store.save()
        #expect(store.exit == .route(.saved(running.id)))
        let stored = try #require(try await scene.stores.workouts.workout(id: running.id))
        #expect(stored.endedAt == Fixtures.now.addingTimeInterval(900), "the end is the first tap's")
        await task.value
    }

    @Test("Try again asks the session for the end of the first tap, whatever the session keeps of it")
    func tryAgain_asksForTheFirstEnd() async throws {
        let running = try Save.logged(1)
        let date = LockIsolated(Fixtures.now.addingTimeInterval(900))
        let session = RefusingFinishSession(base: FakeWorkoutSessionClient(live: running))
        let scene = try Scene.on(session)
        let (store, task) = await Self.saving(scene, at: date)
        await store.save()
        #expect(store.dialog == .saveFailed)
        date.withValue { $0 += 120 }
        store.send(.retrySave)
        store.send(.dismissFailure)
        #expect(store.isSaving, "the alert's own dismissal after its button changes nothing")
        await store.save()
        let first = Fixtures.now.addingTimeInterval(900)
        #expect(await session.askedToEndAt == [first, first])
        #expect(store.exit == .route(.saved(running.id)))
        await task.value
    }

    @Test("Try again that fails again shows the alert again; nothing is saved twice")
    func tryAgain_failsAgain_showsItAgain() async throws {
        let running = try Save.logged(1)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Self.saving(scene)
        await scene.probe.fail(.materialize, times: 2)
        await store.save()
        #expect(store.dialog == .saveFailed)
        store.send(.retrySave)
        #expect(store.dialog == nil)
        await store.save()
        #expect(store.dialog == .saveFailed)
        #expect(!store.isSaving)
        store.send(.retrySave)
        await store.save()
        #expect(store.exit == .route(.saved(running.id)))
        #expect(await Self.materializes(scene) == 3)
        await task.value
    }

    @Test("Close leaves the cover as the session shows it; Try again then answers nothing: the save is forgotten")
    func close_leavesTheCover_andForgetsTheSave() async throws {
        let running = try Save.logged(1)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Self.saving(scene)
        await scene.probe.fail(.materialize)
        await store.save()
        store.send(.dismissFailure)
        #expect(store.dialog == nil)
        #expect(store.exit == nil)
        #expect(store.model.header?.isEnabled == true)

        // The alert is closed: nothing of the failed save answers any more, also under the sheet.
        store.send(.retrySave)
        store.send(.finish)
        #expect(store.dialog == .finish)
        store.send(.retrySave)
        #expect(!store.isSaving)
        #expect(store.saveAttempt == 1)

        // A new "Save workout" is a new save, and the host completes the end that waited.
        store.send(.finish)
        store.send(.save)
        await store.save()
        #expect(store.exit == .route(.saved(running.id)))
        await task.value
    }

    @Test("After Close, a tap whose change completes the waiting save closes the cover as saved")
    func close_thenATap_completesTheSave() async throws {
        let running = try Save.logged(1)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Self.saving(scene)
        await scene.probe.fail(.materialize)
        await store.save()
        store.send(.dismissFailure)
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1])))
        await store.drain()
        await eventually { store.exit != nil }
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.dialog == nil, "the change was not refused: the workout had ended")
        #expect(try await scene.stores.workouts.workout(id: running.id)?.doneSets == 1)
        await task.value
    }

    @Test("An end the session will not take, and an answer that is not finished, are shown as a failed save")
    func save_otherFailures_areShown() async throws {
        // A date that is not finite: the engine ignores the end (`invalidEndDate`).
        let running = try Save.logged(1)
        let never = LockIsolated(Date(timeIntervalSinceReferenceDate: .nan))
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Self.saving(scene, at: never)
        await store.save()
        #expect(store.dialog == .saveFailed)
        #expect(!store.isSaving)
        #expect(try await scene.holds(running))
        task.cancel()

        // A log this version cannot read whole (`incompleteLog`).
        let host = try await Scene.onHost(live: running)
        await host.probe.pretendUnreadable(1)
        let (second, following) = await Self.saving(host)
        await second.save()
        #expect(second.dialog == .saveFailed)
        #expect(try await host.session.current()?.phase == .live)
        following.cancel()

        // A session that answers with the workout still live.
        let odd = try Scene.on(UnfinishingSession(base: FakeWorkoutSessionClient(live: running)))
        let (third, last) = await Self.saving(odd)
        await third.save()
        #expect(third.dialog == .saveFailed)
        #expect(third.exit == nil)
        last.cancel()
    }
}

/// F10 S7a, criteria 17 and 19: the workout ended by another hand before the save reached the session, or
/// while the sheet showed. Neither is a failure: the session's word closes the cover.
@MainActor
@Suite("WorkoutStore save, ended elsewhere", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSaveEndedElsewhereTests {
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    @Test("A save that finds the workout already ended is no failure: the session's word closes the cover")
    func save_alreadyEnded_isNoFailure() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        // The cover's task is not listening for the moment, so the end below is not heard before the call.
        task.cancel()
        await task.value
        store.send(.save)
        _ = try await scene.fake?.finish(endedAt: Fixtures.now.addingTimeInterval(-5))
        await store.save()
        #expect(store.dialog == .finish)
        #expect(store.isSaving, "until the session says how it ended")
        #expect(store.exit == nil)
        #expect(await scene.asked() == [
            .finished(Fixtures.now.addingTimeInterval(-5)), .finished(Fixtures.now)
        ])
        await store.follow()
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.dialog == nil)
    }

    @Test("Ended by another hand between the tap and the save: the cover closes as the session says", arguments: [
        true, false
    ])
    func save_endedElsewhereFirst_closesAsTheSessionSays(isSaved: Bool) async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.finish)
        store.send(.save)
        if isSaved {
            _ = try await scene.fake?.finish(endedAt: Fixtures.now)
        } else {
            try await scene.fake?.discard(endedAt: Fixtures.now)
        }
        await task.value
        await store.save()
        #expect(store.exit == .route(isSaved ? .saved(running.id) : .discarded))
        #expect(store.dialog == nil)
        #expect(await scene.asked().count == 1, "the store asked the session for nothing more")
    }

    @Test("A workout ended elsewhere while the sheet shows closes the cover, sheet included")
    func endedElsewhere_underTheSheet_closes() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.finish)
        try await scene.fake?.discard(endedAt: Fixtures.now)
        await task.value
        #expect(store.dialog == nil)
        #expect(store.exit == .route(.discarded))
        store.send(.save)
        #expect(!store.isSaving)
    }
}
