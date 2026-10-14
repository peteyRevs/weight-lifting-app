import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, criteria 1, 3, 4, 8, 10 and 13: "Finish" opens the sheet, and "Save workout" saves once.
/// Against the fake session, which records what it was asked, and the real host over the in-memory stores.
/// `save()` is what the root's `.task(id: store.saveAttempt)` runs; the tests call it. The taps made
/// before a save, and a change refused under the sheet, are `WorkoutStoreSaveQueueTests`'.
@MainActor
@Suite("WorkoutStore save", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSaveTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Scene = WorkoutScene

    /// The seed workout with its first `count` sets logged, a minute apart.
    static func logged(_ count: Int) throws -> WorkoutState {
        try WorkoutPreview.logged(count, in: Fixtures.seedSession())
    }

    /// A date that moves only when the test moves it.
    static func moving(_ date: LockIsolated<Date>) -> (inout DependencyValues) -> Void {
        { $0.date = DateGenerator { date.value } }
    }

    // MARK: Criteria 1, 3 and 4: the sheet

    @Test("Finish opens the sheet with the workout's line; Keep lifting takes it down and changes nothing")
    func finish_opensTheSheet_keepLiftingReturns() async throws {
        let running = try Self.logged(2)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        #expect(store.finishSheet != nil)
        store.send(.finish)
        #expect(store.dialog == .finish)
        let sheet = try #require(store.finishSheet)
        let moved = running.volume.formatted(in: .lb)
        #expect(sheet.summary == "2 of \(running.totalSets) sets logged · \(moved) lb moved")
        #expect(running.volume > .zero)
        #expect(sheet.canSave)
        store.send(.keepLifting)
        #expect(store.dialog == nil)
        #expect(await scene.asked() == [])
        #expect(try await scene.holds(running))
        task.cancel()
    }

    @Test("The sheet follows the workout: a tap that lands while it is up redraws its line, and it stays")
    func sheet_followsTheWorkout() async throws {
        let running = try Fixtures.seedSession()
        let first = Pump.sets(0, of: running)[0]
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        store.send(.finish)
        #expect(store.finishSheet?.canSave == false, "the tap has not landed yet")
        await store.drain()
        await eventually { store.finishSheet?.canSave == true }
        #expect(store.dialog == .finish)
        #expect(store.finishSheet?.summary.hasPrefix("1 of ") == true)
        // A set logged elsewhere, too.
        let second = running.exercises[0].sets[1]
        try await scene.fake?.apply(.setLogged(
            exerciseIndex: 0, setID: second.id, weight: second.weight, reps: second.reps, doneAt: Fixtures.now
        ))
        await eventually { store.finishSheet?.summary.hasPrefix("2 of ") == true }
        #expect(store.dialog == .finish)
        task.cancel()
    }

    @Test("With no set logged, Save workout changes nothing and calls nothing: the guard is the store's")
    func save_zeroSets_doesNothing() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.finish)
        #expect(store.finishSheet?.canSave == false)
        store.send(.save)
        #expect(!store.isSaving)
        #expect(store.saveAttempt == 0)
        #expect(store.dialog == .finish)
        await store.save()
        #expect(await scene.asked() == [])
        #expect(store.exit == nil)
        // Discard and Keep lifting still answer.
        store.send(.keepLifting)
        #expect(store.dialog == nil)
        store.send(.finish)
        store.send(.discard)
        #expect(store.isDiscarding)
        task.cancel()
    }

    // MARK: Criteria 8, 10 and 13: the save

    @Test("Save workout saves once, ended at the time of the tap, and closes the cover onto the saved workout")
    func save_savesOnce_endedAtTheTap() async throws {
        let running = try Self.logged(3)
        let date = LockIsolated(Fixtures.now.addingTimeInterval(600))
        let scene = try Scene.onFake(live: running)
        let store = scene.store(Self.moving(date))
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        store.send(.finish)
        store.send(.save)
        store.send(.save)
        #expect(store.isSaving)
        #expect(store.saveAttempt == 1)
        #expect(store.dialog == .finish, "the sheet stays up while it saves")
        #expect(store.finishSheet?.isEnabled == false)
        #expect(store.finishSheet?.canSave == false)
        #expect(store.model.header?.isEnabled == false)
        #expect(store.model.page?.isEnabled == false)

        // Every other intent does nothing while it saves.
        for action in [WorkoutAction.keepLifting, .discard, .minimize, .finish, .dismissFailure, .retrySave] {
            store.send(action)
        }
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[4])))
        #expect(store.dialog == .finish)
        #expect(!store.isDiscarding)
        #expect(store.exit == nil)
        #expect(store.queue.isEmpty)

        // The clock moves on before the task runs: the end is the tap's.
        date.withValue { $0 += 45 }
        await store.save()
        await store.save()
        #expect(await scene.asked() == [.finished(Fixtures.now.addingTimeInterval(600))])
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.dialog == nil)
        #expect(try await scene.session.current() == nil)
        await task.value
        #expect(store.exit == .route(.saved(running.id)), "the stream's own word of the end changes nothing")
    }

    @Test("Saved through the host: the workout is in history once, with its end, and nothing is live")
    func save_onTheHost_isInHistory() async throws {
        let running = try Self.logged(2)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        store.send(.finish)
        store.send(.save)
        await store.save()
        #expect(store.exit == .route(.saved(running.id)))
        let stored = try #require(try await scene.stores.workouts.workout(id: running.id))
        #expect(stored.phase == .finished)
        #expect(stored.endedAt == Fixtures.now)
        #expect(stored.doneSets == 2)
        #expect(try await scene.session.current() == nil)
        await task.value
    }

    @Test("The finished workout is felt once, by the stream, whichever of the answer and the update comes first")
    func save_playsWorkoutFinishedOnce() async throws {
        let haptics = FakeHaptics()
        let scene = try Scene.onFake(live: Self.logged(1))
        let store = scene.store { $0.haptics = haptics }
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        store.send(.save)
        await store.save()
        await task.value
        #expect(await haptics.played == [.workoutFinished])

        // The update first: the save's own answer comes after the cover has its exit.
        let other = FakeHaptics()
        let gate = Gate()
        let live = try Self.logged(1)
        let held = try Scene.on(HeldFinishSession(base: FakeWorkoutSessionClient(live: live), gate: gate))
        let second = held.store { $0.haptics = other }
        let following = Task { await second.follow() }
        await eventually { second.shown != nil }
        second.send(.save)
        let saving = Task { await second.save() }
        await gate.waitForArrival()
        await gate.open()
        await saving.value
        await following.value
        #expect(second.exit == .route(.saved(live.id)))
        #expect(await other.played == [.workoutFinished])
    }
}
