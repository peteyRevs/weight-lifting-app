@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S4 criteria 5 and 7: the cover's store against overlap. A discard that is running, a workout
/// that ends under a dialog, taps that arrive late (rows L21 to L24 under pressure).
@MainActor
@Suite("Workout store (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutStoreAdversarialTests {
    typealias World = AdversarialWorld

    /// A store that follows a live workout, that workout, and the task that follows.
    struct Followed {
        let store: WorkoutStore
        let live: WorkoutState
        let task: Task<Void, Never>
    }

    /// A store following a live workout of day 0, and the task that follows.
    func following(_ world: World) async throws -> Followed {
        let live = try await world.begin(day: 0)
        let store = WorkoutStore()
        let task = Task { await store.follow() }
        await eventually("the first update") { store.onScreen != nil }
        await world.session.clearCalls()
        return Followed(store: store, live: live, task: task)
    }

    @Test(
        "L22: a discard the session refuses is shown, the workout stays, and a second try works",
        arguments: World.Kind.allCases
    )
    func discard_refused_isShownAndCanBeRetried(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            let live = followed.live
            defer { task.cancel() }
            await world.session.fail(.discard)
            store.send(.finish)
            store.send(.discard)
            #expect(
                store.isDiscarding && store.model.drawnHeader?.isEnabled == false,
                "the header answers while a discard runs"
            )
            await store.discard()
            #expect(store.dialog == .discardFailed)
            #expect(!store.isDiscarding)
            #expect(store.exit == nil)
            #expect(store.onScreen?.id == live.id)
            #expect(try await unchanged(world.live(), live))
            let alert = WorkoutPresentation.discardFailedAlert
            let words = "\(alert.title) / \(alert.message) / \(alert.dismiss)"
            #expect(words == "Couldn't discard this workout / It's still in progress. Try again. / OK")

            store.send(.dismissFailure)
            #expect(store.dialog == nil)
            #expect(store.model.drawnHeader?.isEnabled == true)
            store.send(.finish)
            store.send(.discard)
            await store.discard()
            await eventually("the cover to close") { store.exit != nil }
            #expect(store.exit == .route(.discarded))
            let after = try await world.live()
            #expect(after?.id == nil)
        }
    }

    @Test("Over the host, a discard whose log cannot be dropped is shown as failed, and the second try ends it")
    func discard_hostCannotDropTheLog_retryEndsIt() async throws {
        try await World.run(.host) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            let live = followed.live
            defer { task.cancel() }
            await world.hostStores.fail(.compact)
            store.send(.finish)
            store.send(.discard)
            await store.discard()
            #expect(
                store.dialog == .discardFailed,
                "\(String(describing: store.dialog)) \(String(describing: store.exit))"
            )
            #expect(store.onScreen?.id == live.id)
            store.send(.dismissFailure)
            store.send(.finish)
            store.send(.discard)
            await store.discard()
            await eventually("the cover to close") { store.exit != nil }
            #expect(store.exit == .route(.discarded))
            let saved = try await world.stores.workouts.workout(id: live.id)
            #expect(saved?.id == nil, "a discarded workout reaches no history")
        }
    }

    @Test(
        "\"Minimize\" while a discard runs does not report a minimized workout that is then gone",
        arguments: World.Kind.allCases
    )
    func minimize_whileDiscarding_doesNotLie(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            defer { task.cancel() }
            await world.session.hold(.discard)
            store.send(.finish)
            store.send(.discard)
            let running = Task { await store.discard() }
            await world.session.waitUntilHeld()
            store.send(.minimize)
            store.send(.finish)
            #expect(store.exit == nil, "minimize was taken while the discard ran: \(String(describing: store.exit))")
            #expect(store.dialog != .finish)
            await world.session.release()
            await running.value
            await eventually("the cover to close") { store.exit != nil }
            #expect(store.exit == .route(.discarded))
            let after = try await world.live()
            #expect(after?.id == nil)
        }
    }

    @Test("\"Discard\" tapped twice, and its work run twice, discards once", arguments: World.Kind.allCases)
    func discard_twice_discardsOnce(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let followed = try await following(world)
            let (store, task) = (followed.store, followed.task)
            defer { task.cancel() }
            store.send(.finish)
            store.send(.discard)
            store.send(.discard)
            #expect(store.discardAttempt == 1)
            await world.session.hold(.discard)
            let first = Task { await store.discard() }
            await world.session.waitUntilHeld()
            await store.discard()
            await world.session.release()
            await first.value
            await store.discard()
            await eventually("the cover to close") { store.exit != nil }
            #expect(await world.session.count(.discard) == 1)
            #expect(store.exit == .route(.discarded))
        }
    }
}

extension WorkoutStore {
    /// The workout the store shows, when it shows one.
    var onScreen: WorkoutState? {
        guard case let .loaded(state) = workout else {
            return nil
        }
        return state
    }
}

extension WorkoutScreenModel {
    var drawnHeader: WorkoutHeaderModel? {
        guard case let .workout(model) = self else {
            return nil
        }
        return model.header
    }
}
