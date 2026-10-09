@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 3 to 5, 7 and 8: the page's taps through the store, against the fake session (which
/// records what it was asked and runs the real engine) and, for a call that waits or fails, the real host
/// over probed in-memory stores. `drain()` is what the root's pump runs for each tap; the tests call it
/// directly, and wait for what the stream shows by observing the store, never by time.
@MainActor
@Suite("WorkoutStore pump", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStorePumpTests {
    typealias Scene = WorkoutScene

    /// The set ids of exercise `index` of `workout`.
    static func sets(_ index: Int, of workout: WorkoutState) -> [SetID] {
        workout.exercises[index].sets.map(\.id)
    }

    /// What the store's page shows of its card: each row's weight and state.
    static func rows(_ store: WorkoutStore) -> [String] {
        (store.model.page?.card?.rows ?? []).map { "\($0.weight) \($0.state)" }
    }

    /// The session's workout, which the test knows to be live.
    static func live(_ scene: Scene) async throws -> WorkoutState {
        try #require(try await scene.session.current())
    }

    // MARK: Criterion 7: in order, each once

    @Test("Two quick taps on \"+\" are two steps, applied in order, each on the workout the one before left")
    func twoQuickSteps_areTwoSteps() async throws {
        let running = try Fixtures.seedSession()
        let first = Self.sets(0, of: running)[0]
        let start = running.exercises[0].sets[0].weight
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: first, .increment)))
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: first, .increment)))
        #expect(await scene.fake?.applied.isEmpty == true, "an intent only queues: the pump applies it")

        await store.drain()
        #expect(await scene.fake?.applied == [
            .setTargetChanged(exerciseIndex: 0, setID: first, weight: start + .pounds(5), reps: nil),
            .setTargetChanged(exerciseIndex: 0, setID: first, weight: start + .pounds(10), reps: nil)
        ])
        let expected = (start + .pounds(10)).formatted(in: .lb)
        await eventually { Self.rows(store).first == "\(expected) active" }
        task.cancel()
    }

    @Test("A double tap on a check logs the set once, and the engine moves the shown row on")
    func doubleTapOnACheck_logsOnce() async throws {
        let running = try Fixtures.seedSession()
        let first = Self.sets(0, of: running)[0]
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        await store.drain()

        let set = running.exercises[0].sets[0]
        #expect(await scene.fake?.applied == [
            .setLogged(exerciseIndex: 0, setID: first, weight: set.weight, reps: set.reps, doneAt: Fixtures.now)
        ])
        await eventually { store.model.page?.card?.rows.first?.state == .done }
        #expect(store.model.page?.card?.rows.map(\.state) == [.done, .active, .pending, .pending, .pending])
        #expect(try await Self.live(scene).cursor == Cursor(exerciseIndex: 0, setIndex: 1), "rule 20")
        task.cancel()
    }

    @Test("Taps of every kind are applied in the order they were made")
    func mixedTaps_areAppliedInOrder() async throws {
        let running = try Fixtures.seedSession()
        let bench = Self.sets(0, of: running)
        let weight = running.exercises[0].sets[2].weight
        let reps = running.exercises[0].sets[2].reps
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        for edit in [
            WorkoutEdit.select(exerciseIndex: 0, setID: bench[2]),
            .stepWeight(exerciseIndex: 0, setID: bench[2], .decrement),
            .stepReps(exerciseIndex: 0, setID: bench[2], .increment),
            .log(exerciseIndex: 0, setID: bench[2]),
            .unlog(exerciseIndex: 0, setID: bench[2]),
            .jump(exerciseIndex: 3)
        ] {
            store.send(.edit(edit))
        }
        await store.drain()
        let lighter = weight - .pounds(5)
        let more = Reps(clamping: reps.value + 1)
        #expect(await scene.fake?.applied == [
            .exerciseSelected(exerciseIndex: 0, setIndex: 2),
            .setTargetChanged(exerciseIndex: 0, setID: bench[2], weight: lighter, reps: nil),
            .setTargetChanged(exerciseIndex: 0, setID: bench[2], weight: nil, reps: more),
            .setLogged(exerciseIndex: 0, setID: bench[2], weight: lighter, reps: more, doneAt: Fixtures.now),
            .setUnlogged(exerciseIndex: 0, setID: bench[2]),
            .exerciseSelected(exerciseIndex: 3, setIndex: 0)
        ])
        #expect(store.selection == WorkoutSelection(exerciseIndex: 3, setID: Self.sets(3, of: running)[0]))
        await eventually { store.model.header?.progressValue == "Exercise 4 of 5" }
        task.cancel()
    }

    @Test(
        "While one tap's call waits in the store, later taps wait their turn: none lost, none planned on stale state"
    )
    func heldApply_laterTapsWaitTheirTurn() async throws {
        let running = try Fixtures.seedSession()
        let first = Self.sets(0, of: running)[0]
        let start = running.exercises[0].sets[0].weight
        let scene = try await Scene.onHost(live: running)
        let (store, task) = await scene.following()
        let before = Self.rows(store)

        await scene.probe.hold(.append)
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: first, .increment)))
        let draining = Task { await store.drain() }
        try await scene.probe.waitUntilHeld()
        // Three more taps arrive while the first is in the store, and a second drain is asked for.
        store.send(.edit(.stepWeight(exerciseIndex: 0, setID: first, .increment)))
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        await store.drain()
        #expect(await scene.appends() == 1, "the second tap has not been sent while the first waits")
        #expect(Self.rows(store) == before, "the page shows what the session last said")
        let isUntouched = try await scene.holds(running)
        #expect(isUntouched)

        await scene.probe.release()
        await draining.value
        #expect(await scene.appends() == 3, "two steps and one log: the second log found the set logged")
        let after = try await Self.live(scene)
        #expect(after.exercises[0].sets[0].weight == start + .pounds(10))
        #expect(after.exercises[0].sets[0].doneAt == Fixtures.now)
        #expect(after.doneSets == 1)
        let expected = (start + .pounds(10)).formatted(in: .lb)
        await eventually { Self.rows(store).first == "\(expected) done" }
        task.cancel()
    }

    @Test(
        "The root's pump applies the taps made before it started and each tap after; a new pump carries on"
    )
    func pump_drainsAsTapsAreMade() async throws {
        let running = try Fixtures.seedSession()
        let bench = Self.sets(0, of: running)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[0])))
        let pump = Task { await store.pump() }
        await eventually { store.model.page?.card?.rows.first?.state == .done }
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[1])))
        await eventually { store.model.page?.card?.rows.dropFirst().first?.state == .done }
        pump.cancel()
        await pump.value

        // The cover's view went away and came back: a tap made in between waits for the new pump.
        store.send(.edit(.log(exerciseIndex: 0, setID: bench[2])))
        let next = Task { await store.pump() }
        await eventually { store.model.page?.card?.rows.dropFirst(2).first?.state == .done }
        #expect(await scene.fake?.applied.count == 3)
        next.cancel()
        task.cancel()
    }

    @Test("A stepper on a row that is not shown makes it the shown row, then changes it")
    func stepOnAnotherRow_selectsItFirst() async throws {
        let running = try Fixtures.seedSession()
        let bench = Self.sets(0, of: running)
        let scene = try Scene.onFake(live: running)
        let (store, task) = await scene.following()
        store.send(.edit(.stepReps(exerciseIndex: 0, setID: bench[2], .increment)))
        await store.drain()
        #expect(await scene.fake?.applied.first == .exerciseSelected(exerciseIndex: 0, setIndex: 2))
        #expect(await scene.fake?.applied.count == 2)
        #expect(try await Self.live(scene).cursor == Cursor(exerciseIndex: 0, setIndex: 2))
        await eventually { store.model.page?.card?.steppers?.setID == bench[2] }
        task.cancel()
    }
}

extension WorkoutScreenModel {
    /// The page, when a workout is on screen.
    var page: WorkoutPageModel? {
        guard case let .workout(workout) = self else {
            return nil
        }
        return workout.page
    }
}
