import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, criteria 9, 11, 12 and 14: the taps made before "Save workout" are applied first and none is
/// lost; a save that would hold no set is not made; a change refused under the sheet wins; "Discard" is
/// unchanged. Against the fake session and, for a call that waits or is refused, the real host over
/// probed in-memory stores.
@MainActor
@Suite("WorkoutStore save and the tap queue", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSaveQueueTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    // MARK: Criteria 9 and 11: the taps made before it

    @Test("Taps queued before Save workout are applied first, in order, each once; then the workout is finished")
    func save_appliesTheQueuedTapsFirst() async throws {
        let running = try Fixtures.seedSession()
        let bench = Pump.sets(0, of: running)
        let scene = try Scene.onFake(live: Save.logged(1))
        let (store, task) = await scene.following()
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: bench[1], .increment)))
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[1])))
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[1])))
        store.send(.finish)
        store.send(.save)
        #expect(await scene.asked() == [], "an intent only queues")
        await store.save()

        #expect(await scene.asked() == [.changed, .changed, .finished(Fixtures.now)])
        #expect(store.doneOnReceipt(of: running.id), "F10 S7b: the receipt shows first; Done closes the cover")
        #expect(store.exit == .route(.saved(running.id)))
        let events = await scene.fake?.applied ?? []
        let heavier = running.exercises[0].sets[1].weight + .pounds(5)
        #expect(events.dropFirst().first == .setLogged(
            exerciseIndex: 0, setID: bench[1], weight: heavier, reps: running.exercises[0].sets[1].reps,
            doneAt: Fixtures.now
        ))
        await task.value
    }

    @Test("A tap still in the store when Save workout is tapped is waited for: finish comes after its answer")
    func save_waitsForTheLastAnswer() async throws {
        let running = try Save.logged(1)
        let second = Pump.sets(0, of: running)[1]
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        await scene.probe.hold(.append)
        store.send(.edit(.log(exerciseIndex: 0, setID: second)))
        let pump = Task { await store.pump() }
        try await scene.probe.waitUntilHeld()
        store.send(.finish)
        store.send(.save)
        let saving = Task { await store.save() }
        await giveWay()
        #expect(await scene.probe.calls.count { $0 == .materialize } == 0, "nothing is saved while the tap waits")
        #expect(store.isSaving)
        #expect(store.exit == nil)

        await scene.probe.release()
        await saving.value
        #expect(store.doneOnReceipt(of: running.id), "F10 S7b: the receipt shows first; Done closes the cover")
        #expect(store.exit == .route(.saved(running.id)))
        let stored = try #require(try await scene.stores.workouts.workout(id: running.id))
        #expect(stored.doneSets == 2, "the set logged before Finish is in the saved workout")
        pump.cancel()
        await task.value
    }

    @Test("When the queue leaves no logged set the workout is not finished, and the sheet shows nothing to save")
    func save_queueLeavesNoSet_isNotSaved() async throws {
        let running = try Save.logged(1)
        let first = Pump.sets(0, of: running)[0]
        let date = LockIsolated(Fixtures.now.addingTimeInterval(600))
        let scene = try Scene.onFake(live: running)
        let store = scene.store(Save.moving(date))
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        store.send(.edit(.unlog(exerciseIndex: 0, setID: first)))
        store.send(.finish)
        store.send(.save)
        #expect(store.isSaving, "the page still showed a logged set")
        await store.save()

        #expect(await scene.asked() == [.changed])
        #expect(!store.isSaving)
        #expect(store.exit == nil)
        #expect(store.dialog == .finish)
        await eventually { store.finishSheet?.canSave == false }
        #expect(store.finishSheet?.isEnabled == true)
        task.cancel()
    }

    // MARK: Criterion 12: a refused change wins

    @Test("A change refused while the save waits withdraws the save: nothing is finished, and the alert shows")
    func refusedUnderTheSave_withdrawsIt() async throws {
        let running = try Save.logged(1)
        let bench = Pump.sets(0, of: running)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        await scene.probe.fail(.append)
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[1])))
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[2])))
        store.send(.finish)
        store.send(.save)
        await store.save()

        #expect(store.dialog == .editFailed)
        #expect(!store.isSaving)
        #expect(store.exit == nil)
        #expect(store.queue.isEmpty, "the taps behind the refused one are dropped")
        #expect(await scene.probe.calls.count { $0 == .materialize } == 0)
        #expect(try await scene.holds(running))
        #expect(store.model.header?.isEnabled == true)

        // After "OK" the cover is as the session last said, and Finish opens the sheet again.
        store.send(.dismissFailure)
        store.send(.finish)
        #expect(store.dialog == .finish)
        #expect(store.finishSheet?.summary.hasPrefix("1 of ") == true)
        store.send(.save)
        await store.save()
        #expect(store.doneOnReceipt(of: running.id), "F10 S7b: the receipt shows first; Done closes the cover")
        #expect(store.exit == .route(.saved(running.id)))
        await task.value
    }

    @Test("A change refused while the sheet only asks takes the sheet down for its alert")
    func refusedUnderTheSheet_showsTheAlert() async throws {
        let running = try Save.logged(1)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        await scene.probe.fail(.append)
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1])))
        store.send(.finish)
        await store.drain()
        #expect(store.dialog == .editFailed)
        #expect(!store.isSaving)
        task.cancel()
    }

    // MARK: Criterion 14: discard is unchanged

    @Test("Discard from the sheet is one tap: the queued taps are dropped and the workout is discarded")
    func discard_fromTheSheet_isOneTap() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1])))
        store.send(.finish)
        store.send(.discard)
        #expect(store.dialog == nil)
        #expect(store.isDiscarding)
        #expect(store.queue.isEmpty)
        store.send(.save)
        #expect(!store.isSaving, "nothing answers while the discard runs")
        await store.discard()
        #expect(await scene.asked() == [.discarded(Fixtures.now)])
        #expect(store.exit == .route(.discarded))
        await task.value
    }
}
