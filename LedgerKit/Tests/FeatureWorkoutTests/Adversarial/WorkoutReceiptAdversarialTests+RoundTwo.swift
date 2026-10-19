import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

// MARK: - G2 round 2: the fix of F10-S7b-1 (`askedEnds`, and the ending update that waits for the answer)

extension WorkoutReceiptAdversarialTests {
    /// A cover on a `KeptEndSession`, its save running and its follow.
    struct KeptCover {
        let store: WorkoutStore
        let follow: Task<Void, Never>
        let saving: Task<Void, Never>
    }

    /// A cover on `session` with one set logged, "Save workout" tapped at `moment`, its save running and its
    /// follow; returns once the session has ended the workout.
    static func savingOnKept(_ session: KeptEndSession, at moment: Date = Fixtures.now) async throws -> KeptCover {
        let scene = try Scene.on(session)
        let store = scene.store { $0.date = .constant(moment) }
        let follow = Task { await store.follow() }
        await eventually { store.shown != nil }
        store.send(.finish)
        store.send(.save)
        let saving = Task { await store.save() }
        await session.waitUntilEnded()
        return KeptCover(store: store, follow: follow, saving: saving)
    }

    @Test(
        "An unknown end waits for an answer that never comes; the tasks starting again close as saved"
    )
    func deferredEnd_answerNever_restartClosesAsSaved() async throws {
        let running = try Save.logged(1)
        let kept = Fixtures.now.addingTimeInterval(-300)
        let session = KeptEndSession(live: running, keptEnd: kept, answerFirst: false)
        let cover = try await Self.savingOnKept(session)
        let (store, follow, saving) = (cover.store, cover.follow, cover.saving)
        await follow.value
        #expect(store.deferredEnd?.endedAt == kept, "the update waits for the answer")
        #expect(store.exit == nil)
        #expect(store.saved == nil)
        #expect(store.isSaving, "nothing times out: the save waits, as under Minimize")

        // The cover's tasks start again while the answer is still out: the new stream says nothing is live.
        saving.cancel()
        await store.follow()
        #expect(store.exit == .route(.saved(running.id)), "O7: the cover did not see the end, it closes as saved")
        #expect(store.saved == nil)
        // The old call answers at last: nothing changes.
        await session.answer()
        await saving.value
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.saved == nil)
        #expect(store.dialog == nil)
    }

    @Test(
        "Another hand's end at an unknown end, with this cover's call out, closes as saved in either order",
        arguments: [
            (KeptEndSession.Answer.noLiveWorkout, false),
            (.noLiveWorkout, true),
            (.refused, false),
            (.refused, true)
        ]
    )
    func unknownEnd_otherAnswers_closeAsSaved(answer: KeptEndSession.Answer, answerFirst: Bool) async throws {
        let running = try Save.logged(1)
        let session = KeptEndSession(
            live: running, keptEnd: Fixtures.now.addingTimeInterval(-5), answerFirst: answerFirst, answer: answer
        )
        let cover = try await Self.savingOnKept(session)
        let (store, follow, saving) = (cover.store, cover.follow, cover.saving)
        await giveWay()
        await session.answer()
        await saving.value
        await follow.value
        await eventually { store.exit != nil || store.saved != nil }
        let order = "\(answer), answer first: \(answerFirst)"
        #expect(store.exit == .route(.saved(running.id)), "\(order)")
        #expect(store.saved == nil, "\(order): another hand's end shows no receipt")
        #expect(store.deferredEnd == nil, "\(order)")
        #expect(!store.isSaving || store.exit != nil, "\(order)")
    }

    @Test("Many refused saves and Closes: each end is kept once, and the last save shows the receipt at the first end")
    func manyRefusals_thenTheReceipt() async throws {
        let running = try Save.logged(1)
        let date = LockIsolated(Fixtures.now.addingTimeInterval(900))
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Failure.saving(scene, at: date)
        let refusals = 5
        for attempt in 0 ..< refusals {
            await scene.probe.fail(.materialize)
            if attempt > 0 {
                date.withValue { $0 += 60 }
                store.send(.finish)
                store.send(.save)
            }
            await store.save()
            #expect(store.dialog == .saveFailed, "refusal \(attempt + 1)")
            // A retry at the same end, refused as well, adds no end.
            await scene.probe.fail(.materialize)
            store.send(.retrySave)
            await store.save()
            #expect(store.dialog == .saveFailed, "retry \(attempt + 1)")
            store.send(.dismissFailure)
        }
        #expect(store.askedEnds.count == refusals, "one end per tap on Save workout, none per Try again")
        date.withValue { $0 += 60 }
        store.send(.finish)
        store.send(.save)
        await store.save()
        await eventually { store.saved != nil || store.exit != nil }
        #expect(store.saved?.id == running.id)
        #expect(
            store.saved?.endedAt == Fixtures.now.addingTimeInterval(900),
            "the first tap's end, as the host kept it"
        )
        #expect(store.exit == nil)
        #expect(store.doneOnReceipt(of: running.id))
        task.cancel()
        await task.value
    }

    @Test("A cover opened after another cover's refused save: its own Save workout shows the receipt at the kept end")
    func reopenedCover_saveShowsTheReceipt() async throws {
        let running = try Save.logged(1)
        let scene = try await Scene.onHost(live: running)
        let first = Fixtures.now.addingTimeInterval(900)
        let (old, oldTask) = await Failure.saving(scene, at: LockIsolated(first))
        await scene.probe.fail(.materialize)
        await old.save()
        old.send(.dismissFailure)
        oldTask.cancel()
        await oldTask.value

        let store = scene.store(Save.moving(LockIsolated(first.addingTimeInterval(600))))
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        #expect(store.askedEnds.isEmpty, "a new cover knows no end")
        store.send(.finish)
        store.send(.save)
        await store.save()
        await eventually { store.saved != nil || store.exit != nil }
        #expect(store.saved?.id == running.id, "the lifter saved it in this cover")
        #expect(store.saved?.endedAt == first)
        #expect(store.exit == nil)
        task.cancel()
        await task.value
    }

    @Test("R10: after Close, the host completing the end on a tap closes as saved, whatever the cover asked before")
    func r10_afterManyCloses_aTapClosesAsSaved() async throws {
        let running = try Save.logged(1)
        let date = LockIsolated(Fixtures.now)
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await Failure.saving(scene, at: date)
        for _ in 0 ..< 2 {
            await scene.probe.fail(.materialize)
            await store.save()
            store.send(.dismissFailure)
            date.withValue { $0 += 60 }
            store.send(.finish)
            store.send(.save)
        }
        await scene.probe.fail(.materialize)
        await store.save()
        store.send(.dismissFailure)
        #expect(store.askedEnds.count == 3)
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1])))
        await store.drain()
        await eventually { store.exit != nil || store.saved != nil }
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.saved == nil, "no save is running: R10, no receipt")
        await task.value
    }
}
