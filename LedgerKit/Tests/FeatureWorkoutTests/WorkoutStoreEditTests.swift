@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 3 to 5 and 8: a change the session refuses, a tap that comes too late, and each kind of
/// tap through the engine. The fixtures are `WorkoutStorePumpTests`'.
@MainActor
@Suite("WorkoutStore edits", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreEditTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Scene = WorkoutScene

    // MARK: Criterion 8: a change the session refuses

    @Test(
        "A refused change is shown; the page stays as the session last said; the taps behind it are dropped"
    )
    func refusedApply_isShown_andThePageStays() async throws {
        let running = try Fixtures.seedSession()
        let first = Pump.sets(0, of: running)[0]
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        let before = Pump.rows(store)

        await scene.probe.fail(.append)
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: first, .increment)))
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: first, .increment)))
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        await store.drain()
        #expect(store.dialog == .editFailed)
        #expect(await scene.appends() == 1, "the taps made behind the refused one were not sent")
        #expect(Pump.rows(store) == before)
        let isUntouched = try await scene.holds(running)
        #expect(isUntouched)
        #expect(store.exit == nil)
        let alert = WorkoutPresentation.editFailedAlert
        #expect("\(alert.title) / \(alert.message) / \(alert.dismiss)" == "Couldn't save that change / Try again. / OK")

        store.send(.dismissFailure)
        #expect(store.dialog == nil)
        // The next tap starts from the workout as it is, not from a step that never happened.
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: first, .increment)))
        await store.drain()
        let after = try await Pump.live(scene)
        #expect(after.exercises[0].sets[0].weight == running.exercises[0].sets[0].weight + .pounds(5))
        #expect(store.dialog == nil)
        task.cancel()
    }

    @Test("A tap on a workout that ended elsewhere is no failure: the cover closes as the session says")
    func applyAfterTheWorkoutEnded_isNoFailure() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let store = scene.store()
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        // The store has not heard yet: it is asked to drain in the same turn as the discard.
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[0])))
        try await scene.session.discard(endedAt: Fixtures.now)
        await store.drain()
        #expect(store.dialog == nil)
        await eventually { store.exit != nil }
        #expect(store.exit == .route(.discarded))
        await task.value
    }

    @Test("While a discard runs, and once the cover is closing, a tap on the page changes nothing")
    func busyOrClosing_tapsDoNothing() async throws {
        let running = try Fixtures.seedSession()
        let first = Pump.sets(0, of: running)[0]
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.stepReps(exerciseIndex: 0, setID: first, .increment)))
        store.send(.finish)
        store.send(.discard)
        #expect(store.model.page?.isEnabled == false)
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        await store.drain()
        #expect(
            await scene.fake?.applied.isEmpty == true,
            "the tap that waited is not applied to a workout being discarded"
        )

        let other = try Scene.onFake(live: running)
        let (closing, closingTask) = await other.following()
        closing.send(.minimize)
        closing.send(.edit(.log(exerciseIndex: 0, setID: first)))
        await closing.drain()
        #expect(await other.fake?.applied.isEmpty == true)
        task.cancel()
        closingTask.cancel()
    }

    // MARK: Criteria 3 to 5 through the engine

    @Test("Logging sends one event and no rest event: the engine starts the rest itself")
    func log_sendsNoRestEvent() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: Pump.sets(0, of: running)[0])))
        await store.drain()
        #expect(await scene.fake?.applied.count == 1)
        #expect(try await Pump.live(scene).rest?.endsAt != nil, "auto rest is the engine's")
        task.cancel()
    }

    @Test("Logging hands the shown row back to the engine's cursor; un-logging moves nothing")
    func log_clearsTheChoice_unlogKeepsIt() async throws {
        var running = try Fixtures.seedSession()
        // The first set was logged a minute ago; the engine's cursor is on the second.
        running.exercises[0].sets[0].doneAt = Fixtures.now.addingTimeInterval(-60)
        running.cursor = Cursor(exerciseIndex: 0, setIndex: 1)
        let bench = Pump.sets(0, of: running)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.select(exerciseIndex: 0, setID: bench[3])))
        await store.drain()
        #expect(store.selection == WorkoutSelection(exerciseIndex: 0, setID: bench[3]))
        await eventually { store.model.page?.card?.rows[3].state == .active }

        store.send(.edit(.log(exerciseIndex: 0, setID: bench[3])))
        await store.drain()
        #expect(store.selection == nil)
        // Rule 20: the next row that is not logged after the fourth is the fifth.
        await eventually { store.model.page?.card?.rows[4].state == .active }

        store.send(.edit(.unlog(exerciseIndex: 0, setID: bench[0])))
        await store.drain()
        await eventually { store.model.page?.card?.rows[0].state == .pending }
        #expect(store.model.page?.card?.rows[4].state == .active, "rule 22")
        task.cancel()
    }

    @Test("Repeat gives every set the last workout's weight and reps and leaves the logged ones logged")
    func repeatLast_writesEverySet_keepsDoneFlags() async throws {
        var running = try Fixtures.seedSession()
        running.exercises[0].lastPerformance = LastPerformance(
            date: Fixtures.now.addingTimeInterval(-7 * 86400), sets: 5, reps: 4, load: .pounds(135)
        )
        let bench = Pump.sets(0, of: running)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[0])))
        store.send(.edit(.repeatLast(exerciseIndex: 0)))
        await store.drain()
        let after = try await Pump.live(scene)
        #expect(after.exercises[0].sets.map(\.weight) == Array(repeating: .pounds(135), count: 5))
        #expect(after.exercises[0].sets.map(\.reps.value) == [4, 4, 4, 4, 4])
        #expect(after.exercises[0].sets.map(\.isDone) == [true, false, false, false, false])
        task.cancel()
    }

    @Test(
        "Add set appends a copy of the last row under a new id, and the header's segment widens"
    )
    func addSet_appendsACopy_andTheSegmentWidens() async throws {
        let running = try Fixtures.seedSession()
        let last = try #require(running.exercises[0].sets.last)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        #expect(store.model.header?.segments.first?.length == 5)
        store.send(.edit(.addSet(exerciseIndex: 0)))
        store.send(.edit(.addSet(exerciseIndex: 0)))
        await store.drain()
        let sets = try await Pump.live(scene).exercises[0].sets
        #expect(sets.count == 7)
        #expect(sets.suffix(2).map(\.kind) == [.added, .added])
        #expect(sets.suffix(2).map(\.weight) == [last.weight, last.weight])
        #expect(sets.suffix(2).map(\.reps) == [last.reps, last.reps])
        #expect(Set(sets.map(\.id)).count == 7, "each added set has an id of its own")
        await eventually { store.model.header?.segments.first?.length == 7 }
        #expect(store.model.page?.card?.rows.map(\.label) == ["1", "2", "3", "4", "5", "6", "7"])
        task.cancel()
    }
}
