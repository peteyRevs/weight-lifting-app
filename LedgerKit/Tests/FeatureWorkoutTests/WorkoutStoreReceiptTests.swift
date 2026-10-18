import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7b, criteria 25, 26, 30, 31 and 37: a save made in this cover shows the workout's receipt, and the
/// cover stays up until "Done"; the records line comes from the bests, read once; nothing of the live
/// workout remains. Against the fake session and the test target's doubles. The live record (criterion 36)
/// is `WorkoutStoreLiveRecordTests`'.
@MainActor
@Suite("WorkoutStore receipt", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreReceiptTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    /// Bests the seed workout's first exercise beats with one set of 200 lb × 5 (an estimate of 225 lb).
    static func beatable(_ workout: WorkoutState) -> PersonalRecords.Bests {
        PersonalRecords.Bests(e1RM: [workout.exercises[0].exerciseID: .pounds(220)])
    }

    /// A store over `scene` whose bests are `stats`, following the session until it shows the workout.
    static func following(
        _ scene: Scene,
        stats: BestsSession? = nil,
        _ configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) async -> (store: WorkoutStore, task: Task<Void, Never>) {
        let store = scene.store {
            if let stats {
                $0.statsQueries = stats
            }
            configure(&$0)
        }
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        return (store, task)
    }

    // MARK: Criteria 25 and 26

    @Test("Save workout shows the receipt and the cover stays up; only Done answers, and closes it as saved")
    func save_showsTheReceipt_doneCloses() async throws {
        let running = try Save.logged(2)
        let haptics = FakeHaptics()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Self.following(scene) { $0.haptics = haptics }
        store.send(.finish)
        store.send(.save)
        await store.save()

        #expect(store.saved?.id == running.id)
        #expect(store.saved?.phase == .finished)
        #expect(store.exit == nil, "the cover stays up on the receipt")
        #expect(store.dialog == nil, "the sheet goes down")
        #expect(!store.isSaving)
        let receipt = try #require(store.receipt)
        #expect(store.model == .receipt(receipt))
        #expect(receipt.header.done == "Done")
        #expect(receipt.page.tiles.map(\.value) == ["0:00", "2/18", "2,000"])

        // Nothing but Done answers on the receipt.
        let others: [WorkoutAction] = [
            .minimize, .finish, .keepLifting, .save, .discard, .retrySave, .dismissFailure, .dismissed(.finish),
            .edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[2]))
        ]
        for action in others {
            store.send(action)
        }
        #expect(store.exit == nil)
        #expect(store.dialog == nil)
        #expect(store.queue.isEmpty)
        #expect(store.saveAttempt == 1)
        #expect(store.discardAttempt == 0)

        await task.value
        #expect(store.exit == nil, "the stream's word of the end leaves the receipt up")
        #expect(store.model == .receipt(receipt))
        store.send(.done)
        #expect(store.exit == .route(.saved(running.id)))
        #expect(await haptics.played == [.workoutFinished], "the end is felt once, by the stream")
    }

    @Test("The stream's word of the end, where the save's answer is lost, shows the receipt too")
    func answerLost_streamSaysFinished_showsTheReceipt() async throws {
        let running = try Save.logged(1)
        let gate = Gate()
        let scene = try Scene.on(HeldFinishSession(base: FakeWorkoutSessionClient(live: running), gate: gate))
        let (store, task) = await Self.following(scene)
        store.send(.save)
        let work = Task { await store.save() }
        await gate.waitForArrival()
        // The save's task ends; the session ends the workout all the same, and the stream says so.
        work.cancel()
        await gate.open()
        await work.value
        await task.value
        #expect(store.saved?.id == running.id)
        #expect(store.saved?.endedAt == Fixtures.now)
        #expect(store.exit == nil)
        #expect(store.doneOnReceipt(of: running.id))
        #expect(store.exit == .route(.saved(running.id)))
    }

    @Test("A workout finished by another hand closes the cover as saved with no receipt, whether or not a save waits")
    func endedElsewhere_showsNoReceipt() async throws {
        // No save asked for: the sheet is up, and the workout is finished elsewhere.
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Self.following(scene)
        store.send(.finish)
        _ = try await scene.fake?.finish(endedAt: Fixtures.now)
        await task.value
        #expect(store.exit == .route(.saved(running.id)))
        #expect(store.saved == nil)

        // A save asked for, ended elsewhere first at another end: the session answers `noLiveWorkout`.
        let second = try Scene.onFake(live: running)
        let (other, following) = await Self.following(second)
        following.cancel()
        await following.value
        other.send(.save)
        _ = try await second.fake?.finish(endedAt: Fixtures.now.addingTimeInterval(-5))
        await other.save()
        await other.follow()
        #expect(other.exit == .route(.saved(running.id)))
        #expect(other.saved == nil, "the end is another hand's")
    }

    // MARK: Criterion 37

    @Test("Nothing of the live workout remains on the receipt: no rest, no tick, no announcement")
    func receipt_holdsNothingLive() async throws {
        let running = try Save.logged(1)
        #expect(running.shownRest != nil, "the fixture is resting")
        let announcements = FakeAnnouncements()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Self.following(scene) { $0.announcements = announcements }
        #expect(store.shownRest != nil)
        store.send(.save)
        await store.save()
        await task.value
        #expect(store.shownRest == nil)
        #expect(store.restPanel == nil)
        await store.keepRestTime()
        #expect(await announcements.announced == [], "a rest is never announced on the receipt")
    }
}

extension WorkoutStoreReceiptTests {
    // MARK: Criteria 30 and 31: the records line

    @Test("The records line counts the records the workout set against the bests before it, read once")
    func records_comeFromTheBests() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: Self.beatable(running))
        let (store, task) = await Self.following(scene, stats: stats)
        await store.readBests()
        await store.readBests()
        #expect(await stats.askedFor == [running.id], "the bests are read once")
        store.send(.save)
        await store.save()
        await task.value
        #expect(store.receipt?.page.records == "1 new PR this session")
        let saved = try #require(store.saved)
        #expect(store.records(of: saved).map(\.achievedAt) == [saved.startedAt], "stamped with the start, as F05 does")
    }

    @Test("Bests that cannot be read leave the line out; the rest of the receipt shows; nothing is retried")
    func bestsUnreadable_noLine() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: nil)
        let (store, task) = await Self.following(scene, stats: stats)
        await store.readBests()
        await store.readBests()
        #expect(await stats.askedFor.count == 1, "a failed read is not retried")
        store.send(.save)
        await store.save()
        await task.value
        let receipt = try #require(store.receipt)
        #expect(receipt.page.records == nil)
        #expect(receipt.page.tiles.count == 3)
        #expect(receipt.page.rows.count == running.exercises.count)
    }

    @Test("The receipt does not wait for the bests: it shows without the line, which comes when they answer")
    func bestsPending_receiptShowsFirst() async throws {
        let running = try Save.logged(1)
        let gate = Gate()
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: Self.beatable(running), gate: gate)
        let (store, task) = await Self.following(scene, stats: stats)
        let reading = Task { await store.readBests() }
        await gate.waitForArrival()
        store.send(.save)
        await store.save()
        await task.value
        #expect(store.receipt?.page.records == nil, "shown before the bests answer")
        await gate.open()
        await reading.value
        #expect(store.receipt?.page.records == "1 new PR this session")
    }

    @Test("A deload workout has no record, whatever its bests")
    func deload_hasNoRecords() async throws {
        var running = try Save.logged(1)
        running.isDeload = true
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: Self.beatable(running))
        let (store, task) = await Self.following(scene, stats: stats)
        await store.readBests()
        store.send(.save)
        await store.save()
        await task.value
        #expect(store.receipt != nil)
        #expect(store.receipt?.page.records == nil)
    }

    @Test("The root reads the bests from a task of its own, keyed by the workout on screen")
    func root_readsTheBests() throws {
        let root = try #require(CopyAudit.sources(ofModule: "FeatureWorkout")["WorkoutRoot.swift"])
        let source = SwiftSource(root)
        #expect(FeatureWorkoutSourceTests.lines(of: ".task(id:store.bestsSubject)", in: source).count == 1)
        #expect(FeatureWorkoutSourceTests.lines(of: "awaitstore.readBests()", in: source).count == 1)
    }
}
