import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7b, criterion 36: a set that makes a record the workout did not hold before is felt once, as
/// `.personalRecord`, by the stream that shows it; the records the workout holds when the bests arrive are
/// not felt; an un-log and a second log of the same set are not felt again. Nothing is drawn for it (O10).
@MainActor
@Suite("WorkoutStore live record", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreLiveRecordTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Receipt = WorkoutStoreReceiptTests
    typealias Save = WorkoutStoreSaveTests
    typealias Scene = WorkoutScene

    /// A cover over the fake session following `running`, with the haptics it plays and a date that moves
    /// only when a tap moves it.
    struct Cover {
        let store: WorkoutStore
        let haptics: FakeHaptics
        let task: Task<Void, Never>
        let date: LockIsolated<Date>

        init(_ running: WorkoutState, bests: PersonalRecords.Bests?) async throws {
            let played = FakeHaptics()
            let moment = LockIsolated(Fixtures.now)
            let scene = try Scene.onFake(live: running)
            let stats = BestsSession(base: scene.stores.stats, answer: bests)
            (store, task) = await Receipt.following(scene, stats: stats) {
                $0.haptics = played
                $0.date = DateGenerator { moment.value }
            }
            haptics = played
            date = moment
        }

        /// Sends `edit` as a tap does ten seconds after the last, so that an un-log is not taken for the
        /// second touch of a double tap (`WorkoutEditPlan.undoGuard`); applies it, and waits until the
        /// stream shows `done` sets logged.
        func tap(_ edit: WorkoutEdit, until done: Int) async {
            date.withValue { $0 += 10 }
            store.send(.edit(edit))
            await store.drain()
            await eventually { store.shown?.doneSets == done }
            await giveWay()
        }

        /// How many times a record was felt.
        func records() async -> Int {
            await haptics.played.count { $0 == .personalRecord }
        }

        func close() async {
            task.cancel()
            await task.value
        }
    }

    @Test("A record the workout did not hold is felt once; an un-log and a second log do not feel it again")
    func newRecord_isFeltOnce() async throws {
        let running = try Save.logged(0)
        let sets = Pump.sets(0, of: running)
        let cover = try await Cover(running, bests: Receipt.beatable(running))
        await cover.store.readBests()
        #expect(await cover.records() == 0)

        await cover.tap(.log(exerciseIndex: 0, setID: sets[0]), until: 1)
        #expect(await cover.records() == 1, "the first set beats the best estimate")
        await cover.tap(.unlog(exerciseIndex: 0, setID: sets[0]), until: 0)
        await cover.tap(.log(exerciseIndex: 0, setID: sets[0]), until: 1)
        await cover.tap(.log(exerciseIndex: 0, setID: sets[1]), until: 2)
        #expect(await cover.records() == 1, "the same record of the same exercise, felt once")
        #expect(await cover.haptics.played.first == .setLogged, "the set's own haptic comes first")
        #expect(cover.store.model.page != nil, "nothing is drawn for it")
        await cover.close()
    }

    @Test("Each kind of record is its own: a set that beats both bests is felt twice, once for each")
    func twoKinds_areFeltOnceEach() async throws {
        let running = try Save.logged(0)
        let id = running.exercises[0].exerciseID
        let bests = PersonalRecords.Bests(
            e1RM: [id: .pounds(220)],
            weightAtReps: [id: [Reps(clamping: 5): .pounds(195)]]
        )
        let cover = try await Cover(running, bests: bests)
        await cover.store.readBests()
        await cover.tap(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[0]), until: 1)
        #expect(await cover.records() == 2)
        await cover.close()
    }

    @Test("The records the workout holds when the cover opens are not felt, then or later")
    func heldAtOpen_isNotFelt() async throws {
        let running = try Save.logged(1)
        let cover = try await Cover(running, bests: Receipt.beatable(running))
        await cover.store.readBests()
        await cover.tap(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1]), until: 2)
        #expect(await cover.haptics.played == [.setLogged])
        await cover.close()
    }

    @Test("Before the bests answer, and when they cannot be read, nothing is felt for a record")
    func noBests_nothingFelt() async throws {
        let running = try Save.logged(0)
        let cover = try await Cover(running, bests: nil)
        await cover.tap(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[0]), until: 1)
        await cover.store.readBests()
        await cover.tap(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[1]), until: 2)
        #expect(await cover.haptics.played == [.setLogged, .setLogged])
        await cover.close()
    }
}
