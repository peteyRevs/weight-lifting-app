import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// F18 S6b: the end overlay (criterion 10). It offers "Save workout" once a set is logged and "Discard" only while
/// none is, and the store discards only a workout still without one when the discard's turn comes (orchestrator
/// ruling 7, pending Pete). "Save workout" ends at the summary, "Discard" at idle, and "Keep lifting" goes back to the
/// list; the overlay stands in the live screen's place and stays through a change of mode. A watch test cannot host a
/// view or tap it, so a tap is the overlay's own action, which its control calls.
@MainActor
@Suite("Watch end overlay", .tags(.watch), .timeLimit(.minutes(1)))
struct WatchEndOverlayTests {
    typealias Scene = WatchStoreScene

    static func shown(_ store: WatchWorkoutStore) -> String {
        WatchWorkoutRootTests.shown(store)
    }

    /// The live store, with the end overlay opened from the list as the lifter opens it.
    static func ending(_ live: WorkoutState) async throws -> (WatchWorkoutStore, Task<Void, Never>) {
        let scene = try Scene(live: live)
        let (store, task) = await scene.running()
        store.send(.openList)
        try WatchListOverlay(model: #require(store.list), send: store.send).openEnd()
        #expect(shown(store) == "end" && WatchWorkoutRootTests.draws(store))
        return (store, task)
    }

    /// The end overlay the root draws over `store`, its taps sent to the store.
    static func overlay(_ store: WatchWorkoutStore) throws -> WatchEndOverlay {
        try WatchEndOverlay(model: #require(store.end), send: store.send)
    }

    @Test("Discard is offered only while no set is logged; Save workout only once one is; never both")
    func offersDiscard_onlyWithNothingLogged() throws {
        let fresh = try WatchPresentation.end(Scene.lowerA(), locale: Fixtures.locale)
        #expect(fresh.loggedSetCount == 0 && fresh.offersDiscard && !fresh.canSave)
        for rows in [[(0, 0)], [(0, 0), (0, 1), (2, 0)]] {
            let logged = try WatchPresentation.end(Scene.lowerA(rows), locale: Fixtures.locale)
            #expect(logged.loggedSetCount == rows.count && !logged.offersDiscard && logged.canSave, "\(rows.count)")
        }
        var sent: [WatchAction] = []
        let empty = try WatchEndOverlay(model: #require(EndSample.empty.model), send: { sent.append($0) })
        #expect(empty.save == nil)
        empty.discard?()
        empty.keepLifting()
        let logged = try WatchEndOverlay(model: #require(EndSample.logged.model), send: { sent.append($0) })
        #expect(logged.discard == nil)
        logged.save?()
        #expect(sent == [.discard, .keepLifting, .save])
    }

    @Test("Save workout ends the workout: the summary shows, of a finished workout")
    func save_showsTheSummary() async throws {
        let (store, task) = try await Self.ending(Scene.lowerA([(0, 0)]))
        let save = try #require(Self.overlay(store).save)
        save()
        await observed("the summary") { Self.shown(store) == "summary" }
        #expect(store.workout?.phase == .finished && store.shownOverlay == nil && WatchWorkoutRootTests.draws(store))
        task.cancel()
    }

    @Test("Discard of a workout with nothing logged ends at the screen before a workout")
    func discard_empty_showsIdle() async throws {
        let (store, task) = try await Self.ending(Scene.lowerA())
        let discard = try #require(Self.overlay(store).discard)
        discard()
        await observed("idle") { Self.shown(store) == "idle" }
        #expect(store.workout?.phase == .discarded && store.summary == nil && store.shownOverlay == nil)
        task.cancel()
    }

    @Test("Discard sent with sets logged is refused: the workout stays live, and the overlay stays up with Save")
    func discard_withSetsLogged_isRefused() async throws {
        let (store, task) = try await Self.ending(Scene.lowerA([(0, 0)]))
        store.send(.discard)
        await Scene.settled(store)
        #expect(store.workout?.phase == .live && store.workout?.doneSets == 1)
        #expect(Self.shown(store) == "end")
        #expect(try Self.overlay(store).save != nil && Self.overlay(store).discard == nil)
        task.cancel()
    }

    @Test("A set logged elsewhere after the overlay offered Discard refuses it: the workout stays live with its set")
    func discard_raceWithALoggedSet_isRefused() async throws {
        let scene = try Scene(live: Scene.lowerA())
        let (store, task) = await scene.running()
        store.send(.openEnd)
        let drawn = try Self.overlay(store)
        let discard = try #require(drawn.discard, "nothing logged: Discard is offered")
        let set = try #require(store.workout?.exercises[0].sets[0])
        try await scene.fake?.apply(.setLogged(
            exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: Fixtures.now
        ))
        discard()
        await Scene.settled(store)
        await observed("the set heard") { store.workout?.doneSets == 1 }
        #expect(store.workout?.phase == .live && Self.shown(store) == "end")
        #expect(try Self.overlay(store).save != nil && Self.overlay(store).discard == nil, "the overlay redraws: Save")
        task.cancel()
    }

    @Test("Keep lifting goes back to the list, and the list's back to the live screen")
    func keepLifting_returnsToTheList() async throws {
        let (store, task) = try await Self.ending(Scene.lowerA([(0, 0)]))
        try Self.overlay(store).keepLifting()
        #expect(Self.shown(store) == "list")
        store.send(.closeList)
        #expect(Self.shown(store) == "ready" && store.workout?.phase == .live)
        task.cancel()
    }

    @Test("The end overlay stays up through a change of mode: a rest that starts, and a rest that ends")
    func end_survivesAModeChange() async throws {
        let scene = try Scene(live: Scene.lowerA([(0, 0)]))
        let (store, task) = await scene.running()
        store.send(.openEnd)
        try await scene.fake?.apply(.restStarted(endsAt: Fixtures.now.addingTimeInterval(90), total: .seconds(90)))
        await observed("the rest") { store.rest != nil }
        #expect(Self.shown(store) == "end", "the rest stays under the overlay")
        try await scene.fake?.apply(.restSkipped)
        await observed("set ready") { store.mode == .ready }
        #expect(Self.shown(store) == "end" && WatchWorkoutRootTests.draws(store))
        task.cancel()
    }
}
