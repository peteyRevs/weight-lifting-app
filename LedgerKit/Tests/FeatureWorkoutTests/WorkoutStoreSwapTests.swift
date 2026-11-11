import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8b, criteria 17 to 21 and 25: the swap through the store (the failures are
/// `WorkoutStoreSwapFailureTests`', the program and the records `WorkoutStoreSwapProgramTests`'). "Swap
/// exercise" opens the sheet for the shown exercise; `loadSwap()` is what the root's
/// `.task(id: store.swapAttempt)` runs and `readSwappedBests()` what its `.task(id: store.unreadBests)` runs,
/// so the tests call them. Against the fake session, which records what it was asked, and the real host over
/// the in-memory stores for a refusal, the save and the discard.
/// The workout is the spec's Upper A (`Fixtures.seedSession()`) on the seeded catalog: Barbell Bench Press
/// first, its first alternative Dumbbell Bench Press at 15 lb.
@MainActor
@Suite("WorkoutStore swap", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreSwapTests {
    typealias Pump = WorkoutStorePumpTests
    typealias Scene = WorkoutScene

    /// A cover on `scene` following its session, with the exercise store and the stats `configure` binds.
    static func following(
        _ scene: Scene,
        _ configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) async -> (store: WorkoutStore, task: Task<Void, Never>) {
        let store = scene.store(configure)
        let task = Task { await store.follow() }
        await eventually { store.shown != nil }
        return (store, task)
    }

    /// Opens the sheet and reads its alternatives, as a tap and the root's task do.
    static func open(_ store: WorkoutStore) async throws -> SwapSheetModel {
        store.send(store.cardOpensSwap)
        await store.loadSwap()
        return try #require(store.swapSheet)
    }

    /// The swaps the fake session was asked to apply: the new exercise's name, and the toggle.
    static func swaps(_ scene: Scene) async -> [String] {
        await (scene.fake?.applied ?? []).compactMap { event in
            if case let .exerciseSwapped(_, _, name, alsoUpdateProgram, replacement) = event {
                return "\(name) \(alsoUpdateProgram) \(replacement?.load.formatted(in: .lb) ?? "-")"
            }
            return nil
        }
    }

    // MARK: Criteria 17, 18 and 21: open, read once, Use

    @Test("Swap exercise opens the sheet and reads once: its line, then up to eight rows; no second sheet opens")
    func open_readsOnce() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let exercises = SwapExercises(base: scene.stores.exercises)
        let (store, task) = await Self.following(scene) { $0.exerciseRepository = exercises }
        store.send(store.cardOpensSwap)
        #expect(store.dialog == .swap)
        #expect(store.swapAttempt == 1)
        #expect(store.swapSheet?.rows.isEmpty == true, "nothing is read before the task runs")
        await store.loadSwap()
        let sheet = try #require(store.swapSheet)
        #expect(sheet.rows.count == 8)
        #expect(sheet.rows.first?.name == "Dumbbell Bench Press")
        #expect(sheet.toggle?.isOn == false)
        store.send(store.cardOpensSwap)
        await store.loadSwap()
        #expect(store.swapAttempt == 1, "a second sheet cannot open while the first is up")
        #expect(await exercises.catalogReads == 1)
        task.cancel()
    }

    @Test("While the read is out the sheet shows its line and no row")
    func heldRead_showsNoRows() async throws {
        let gate = Gate()
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let exercises = SwapExercises(base: scene.stores.exercises, gate: gate)
        let (store, task) = await Self.following(scene) { $0.exerciseRepository = exercises }
        store.send(store.cardOpensSwap)
        let load = Task { await store.loadSwap() }
        await gate.waitForArrival()
        let held = try #require(store.swapSheet)
        #expect(held.rows.isEmpty && held.message == nil && held.toggle == nil)
        #expect(held.line == "Same movement pattern.")
        await gate.open()
        await load.value
        #expect(store.swapSheet?.rows.count == 8)
        task.cancel()
    }

    @Test("Use takes the sheet down at once, applies one swap, and the card shows the replacement")
    func use_appliesOneSwap_theCardFollows() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await Self.following(scene)
        let row = try await #require(Self.open(store).rows.first)
        store.send(.edit(row.choose))
        #expect(store.dialog == nil)
        // A second tap on Use, made while the sheet goes, queues nothing.
        store.send(.edit(row.choose))
        await store.drain()
        await eventually { store.model.page?.card?.title == "Dumbbell Bench Press" }
        #expect(await Self.swaps(scene) == ["Dumbbell Bench Press false 15"])
        let card = try #require(store.model.page?.card)
        #expect(card.last == "No history yet")
        #expect(card.repeatLast == nil)
        #expect(card.rows.map(\.weight) == ["15", "15", "15", "15", "15"])
        #expect(card.target == "5 × 5 @ 15 lb · RPE 8")
        let first = try Pump.sets(0, of: Fixtures.seedSession())[0]
        #expect(card.steppers?.setID == first, "the shown row stays the first")
        #expect(card.swap == "Swap exercise", "still nothing logged: it can be swapped again")
        task.cancel()
    }

    @Test("Cancel, and the system's dismissal, take the sheet down and apply nothing")
    func cancel_appliesNothing() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let (store, task) = await Self.following(scene)
        let row = try await #require(Self.open(store).rows.first)
        store.send(.swap(.updateProgram(true)))
        store.send(.swap(.cancel))
        #expect(store.dialog == nil)
        store.send(.edit(row.choose))
        await store.drain()
        #expect(await scene.fake?.applied.isEmpty == true)
        _ = try await Self.open(store)
        #expect(store.swapSheet?.toggle?.isOn == false, "the switch opens from the workout, not the last sheet")
        store.send(.dismissed(.swap))
        #expect(store.dialog == nil)
        task.cancel()
    }

    @Test("The taps made before Use are applied first, in order; then the swap, as one event")
    func queuedTaps_areAppliedFirst() async throws {
        let running = try Fixtures.seedSession()
        let first = Pump.sets(0, of: running)[0]
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Self.following(scene)
        store.send(.edit(.stepReps(exerciseIndex: 0, setID: first, .increment)))
        let row = try await #require(Self.open(store).rows.first)
        store.send(.edit(row.choose))
        await store.drain()
        let applied = await scene.fake?.applied ?? []
        #expect(applied.count == 2)
        if case .setTargetChanged = applied.first {} else {
            Issue.record("the step was applied first")
        }
        #expect(await Self.swaps(scene).count == 1)
        task.cancel()
    }

    // MARK: Criteria 19 and 25: the workout moves under the sheet

    @Test("A set logged under the sheet takes it down; a Use queued behind it comes to nothing")
    func setLoggedUnderTheSheet() async throws {
        let running = try Fixtures.seedSession()
        let first = Pump.sets(0, of: running)[0]
        let scene = try Scene.onFake(live: running)
        let (store, task) = await Self.following(scene)
        let row = try await #require(Self.open(store).rows.first)
        store.send(.edit(.log(exerciseIndex: 0, setID: first)))
        store.send(.edit(row.choose))
        await store.drain()
        #expect(await Self.swaps(scene).isEmpty, "the plan refuses a choice for an exercise with a set logged")
        #expect(store.model.page?.card?.title == "Barbell Bench Press")

        _ = try await Self.open(store)
        #expect(store.dialog == nil, "with a set logged, Swap exercise opens nothing")
        let second = running.exercises[1].sets[0]
        store.send(.edit(.jump(exerciseIndex: 1)))
        await store.drain()
        _ = try await Self.open(store)
        #expect(store.dialog == .swap)
        try await scene.fake?.apply(.setLogged(
            exerciseIndex: 1, setID: second.id, weight: second.weight, reps: second.reps, doneAt: Fixtures.now
        ))
        await eventually { store.dialog == nil }
        task.cancel()
    }
}
