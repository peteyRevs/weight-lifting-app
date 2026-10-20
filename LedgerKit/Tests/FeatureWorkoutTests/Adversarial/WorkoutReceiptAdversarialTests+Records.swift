import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

// MARK: - Criteria 30 and 36: the records and the live record

extension WorkoutReceiptAdversarialTests {
    @Test("O5: one set that beats both bests is two records on the receipt")
    func oneSet_twoRecords_countsTwo() async throws {
        let running = try Save.logged(1)
        let id = running.exercises[0].exerciseID
        let bests = PersonalRecords.Bests(
            e1RM: [id: .pounds(220)],
            weightAtReps: [id: [Reps(clamping: 5): .pounds(195)]]
        )
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: bests)
        let (store, task) = await Receipt.following(scene, stats: stats)
        await store.readBests()
        store.send(.save)
        await store.save()
        await task.value
        #expect(store.receipt?.page.records == "2 new PRs this session")
    }

    @Test("A bests read that fails is logged once and never retried, even when the cover's tasks start again")
    func failedRead_notRetried_acrossARestart() async throws {
        let running = try Save.logged(1)
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: nil)
        let (store, task) = await Receipt.following(scene, stats: stats)
        await store.readBests()
        task.cancel()
        await task.value
        let again = Task { await store.follow() }
        await eventually { store.shown != nil }
        await store.readBests()
        #expect(await stats.askedFor.count == 1)
        store.send(.save)
        await store.save()
        await again.value
        #expect(store.receipt?.page.records == nil)
        #expect(store.receipt?.page.rows.count == running.exercises.count)
    }

    /// F10-S7b-2. Criterion 36: the records not played are those the workout holds **when the cover opens**.
    /// A set logged in this cover before the bests answer is a record the workout did not hold then.
    @Test("A record set in this cover before the bests answer is felt once they do")
    func recordBeforeTheBestsAnswer_isFelt() async throws {
        let running = try Save.logged(0)
        let sets = Pump.sets(0, of: running)
        let haptics = FakeHaptics()
        let moment = LockIsolated(Fixtures.now)
        let gate = Gate()
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: Receipt.beatable(running), gate: gate)
        let (store, task) = await Receipt.following(scene, stats: stats) {
            $0.haptics = haptics
            $0.date = DateGenerator { moment.value }
        }
        let reading = Task { await store.readBests() }
        await gate.waitForArrival()

        moment.withValue { $0 += 10 }
        store.send(.edit(.log(exerciseIndex: 0, setID: sets[0])))
        await store.drain()
        await eventually { store.shown?.doneSets == 1 }
        await gate.open()
        await reading.value
        moment.withValue { $0 += 10 }
        store.send(.edit(.log(exerciseIndex: 0, setID: sets[1])))
        await store.drain()
        await eventually { store.shown?.doneSets == 2 }
        await giveWay()
        #expect(await haptics.played.count { $0 == .personalRecord } == 1, "the first set beat the best estimate")
        task.cancel()
        await task.value
    }

    @Test("A heavier set later is the same record: not felt again; another exercise's record is its own")
    func laterHeavierSet_sameRecord_otherExerciseOwn() async throws {
        let running = try Save.logged(0)
        let first = running.exercises[0].exerciseID
        let second = running.exercises[1].exerciseID
        let bests = PersonalRecords.Bests(e1RM: [first: .pounds(220), second: .pounds(1)])
        let haptics = FakeHaptics()
        let moment = LockIsolated(Fixtures.now)
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: bests)
        let (store, task) = await Receipt.following(scene, stats: stats) {
            $0.haptics = haptics
            $0.date = DateGenerator { moment.value }
        }
        await store.readBests()
        var done = 0
        for (exercise, setID) in [
            (0, Pump.sets(0, of: running)[0]),
            (0, Pump.sets(0, of: running)[1]),
            (1, Pump.sets(1, of: running)[0])
        ] {
            moment.withValue { $0 += 10 }
            store.send(.edit(.log(exerciseIndex: exercise, setID: setID)))
            await store.drain()
            done += 1
            let wanted = done
            await eventually { store.shown?.doneSets == wanted }
        }
        await giveWay()
        #expect(await haptics.played.count { $0 == .personalRecord } == 2, "one for each exercise")
        task.cancel()
        await task.value
    }

    @Test("Nothing is felt for a record on the receipt, and the receipt's records line counts every record")
    func receipt_noLiveRecordAfterTheSave() async throws {
        let running = try Save.logged(1)
        let haptics = FakeHaptics()
        let scene = try Scene.onFake(live: running)
        let stats = BestsSession(base: scene.stores.stats, answer: Receipt.beatable(running))
        let (store, task) = await Receipt.following(scene, stats: stats) { $0.haptics = haptics }
        await store.readBests()
        store.send(.save)
        await store.save()
        await task.value
        #expect(store.receipt?.page.records == "1 new PR this session", "held at open, still on the receipt")
        #expect(await haptics.played == [.workoutFinished], "held at open: never felt")
        #expect(store.shownRest == nil)
        #expect(store.restPanel == nil)
    }
}
