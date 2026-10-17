@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Rows L18 to L28: the cover while it is up.
extension WorkoutLifecycleAdversarialTests {
    @Test(
        "L18, L19, L20: minimize keeps the workout; Finish asks; \"Keep lifting\" changes nothing",
        arguments: World.Kind.allCases
    )
    func finish_keepLifting_changesNothing(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let live = try #require(try await world.live())
            await world.session.clearCalls()

            await rig.tap(.finish)
            #expect(rig.store?.dialog == .finish)
            #expect(rig.phase == .cover)
            await rig.tap(.keepLifting)
            #expect(rig.store?.dialog == nil)
            #expect(rig.phase == .cover)
            #expect(unchanged(rig.shown, live))
            #expect(try await unchanged(world.live(), live))
            let writes = await world.session.calls.filter { $0 != .current && $0 != .updates }
            #expect(writes.isEmpty)
            #expect(rig.routes.isEmpty)
        }
    }

    @Test(
        "L21: Finish, then Discard, ends the workout, closes the cover and leaves nothing",
        arguments: World.Kind.allCases
    )
    func finish_discard_endsTheWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let live = try #require(try await world.live())
            await rig.tap(.finish)
            await rig.tap(.discard)
            #expect(rig.phase == .idle)
            #expect(rig.routes == [.discarded])
            do {
                let found = try await world.live()
                #expect(found?.id == nil)
            }
            do {
                let found = try await world.stores.workouts.workout(id: live.id)
                #expect(found?.id == nil)
            }
            #expect(await world.session.count(.discard) == 1)

            // And the next start is a new workout, not the old one back.
            await rig.start(world.source(day: 0))
            #expect(rig.phase == .cover)
            #expect(rig.shown != nil)
            #expect(rig.shown?.id != live.id)
        }
    }

    @Test("L23, L24: a workout ended by another hand closes the cover and says how", arguments: World.Kind.allCases)
    func endedElsewhere_closesTheCover(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let first = try #require(try await world.live())
            _ = try await world.truth.finish(endedAt: Fixtures.now.addingTimeInterval(60))
            await rig.absorb(nil)
            #expect(rig.phase == .idle)
            #expect(rig.routes == [.saved(first.id)])
            #expect(rig.store == nil)

            await rig.start(world.source(day: 0))
            let second = try #require(try await world.live())
            #expect(second.id != first.id)
            #expect(rig.shown?.id == second.id)
            try await world.truth.discard(endedAt: Fixtures.now.addingTimeInterval(120))
            await rig.absorb(nil)
            #expect(rig.phase == .idle)
            #expect(rig.routes == [.saved(first.id), .discarded])
            do {
                let found = try await world.live()
                #expect(found?.id == nil)
            }
        }
    }

    @Test("L28: with the cover up, a start for another day changes nothing", arguments: World.Kind.allCases)
    func coverUp_startOtherDay_isIgnored(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let live = try #require(try await world.live())
            await world.session.clearCalls()
            await rig.start(world.source(day: 1))
            await rig.resume()
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == live.id)
            #expect(try await unchanged(world.live(), live))
            #expect(rig.covers == 1)
            #expect(await world.session.count(.start) == 0)
            #expect(await world.session.count(.discard) == 0)
        }
    }

    @Test("A change made by another hand while the cover is up is shown", arguments: World.Kind.allCases)
    func changedElsewhere_isShown(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let live = try #require(try await world.live())
            let set = try #require(live.exercises.first?.sets.first)
            let next = try await world.truth.apply(
                .setLogged(exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: Fixtures.now)
            )
            await rig.absorb(next)
            #expect(rig.shown?.exercises.first?.sets.first?.doneAt != nil)
            #expect(rig.phase == .cover)
        }
    }
}
