@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S4: the tester's lifecycle table (test-findings, "Slice S4 — round 1"), rows L1 to L11 and L18
/// to L24, each over the fake and over the real host on in-memory stores.
@MainActor
@Suite("Workout lifecycle (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutLifecycleAdversarialTests {
    typealias World = AdversarialWorld

    @Test("L1: with nothing live, a start makes one workout and the cover shows it", arguments: World.Kind.allCases)
    func start_nothingLive_showsTheNewWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let live = try #require(try await world.live())
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == live.id)
            #expect(live.source == world.source(day: 0))
            #expect(live.name == world.program.days[0].name)
            #expect(live.startedAt == Fixtures.now)
            #expect(live.exercises.flatMap(\.sets).allSatisfy { $0.doneAt == nil })
            #expect(await world.session.count(.start) == 1)
            #expect(rig.routes.isEmpty)
        }
    }

    @Test(
        "L4, L6: a live workout is shown again by its own day and by resume, as it is",
        arguments: World.Kind.allCases
    )
    func startSameDay_andResume_showTheLiveWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.start(world.source(day: 0))
            let first = try #require(try await world.live())
            await rig.tap(.minimize)
            #expect(rig.phase == .idle)
            #expect(rig.routes == [.minimized])
            #expect(try await world.live()?.id == first.id)

            world.clock.setValue(Fixtures.now.addingTimeInterval(1462))
            await world.session.clearCalls()
            let before = await world.useCaseStarts()
            await rig.start(world.source(day: 0))
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == first.id)
            #expect(rig.shown?.startedAt == Fixtures.now, "the elapsed time is the workout's, not the reopening's")
            #expect(await world.session.count(.start) == 0)
            #expect(await world.useCaseStarts() == before, "criterion 3: the use case is not asked for the live day")

            await rig.tap(.minimize)
            await rig.resume()
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == first.id)
            #expect(rig.covers == 3)
            #expect(await world.session.count(.start) == 0)
            #expect(await world.session.count(.discard) == 0)
        }
    }

    @Test("L7: resume with nothing live shows nothing and says nothing", arguments: World.Kind.allCases)
    func resume_nothingLive_doesNothing(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await rig.resume()
            #expect(rig.phase == .idle)
            #expect(rig.covers == 0)
            do {
                let found = try await world.live()
                #expect(found?.id == nil)
            }
            #expect(await world.session.count(.start) == 0)
        }
    }

    @Test("L8, L11: another day asks, and cancel changes nothing", arguments: World.Kind.allCases)
    func otherDay_asks_andCancelChangesNothing(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            await rig.start(world.source(day: 1))
            #expect(rig.phase == .conflict(world.source(day: 1)))
            #expect(rig.covers == 0)
            #expect(try await world.live()?.id == first.id)

            await rig.answer(.cancelConflict)
            #expect(rig.phase == .idle)
            #expect(try await unchanged(world.live(), first))
            #expect(await world.session.count(.start) == 0)
            #expect(await world.session.count(.discard) == 0)
            #expect(await world.session.count(.apply) == 0)
            #expect(rig.covers == 0)
        }
    }

    @Test("L9: \"Resume it\" shows the live workout and starts nothing", arguments: World.Kind.allCases)
    func conflict_resumeIt_showsTheLiveWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            await rig.start(world.source(day: 1))
            await rig.answer(.resumeLive)
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == first.id)
            #expect(try await unchanged(world.live(), first))
            #expect(await world.session.count(.start) == 0)
            #expect(await world.session.count(.discard) == 0)
        }
    }

    @Test("L10: \"Discard and start new\" discards, then starts, and shows the new one", arguments: World.Kind.allCases)
    func conflict_replace_discardsThenStarts(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            await rig.start(world.source(day: 1))
            await world.session.clearCalls()
            await rig.answer(.replaceLive(world.source(day: 1)))
            let live = try #require(try await world.live())
            #expect(live.id != first.id)
            #expect(live.source == world.source(day: 1))
            #expect(rig.phase == .cover)
            #expect(rig.shown?.id == live.id)
            let order = await world.session.calls.filter { $0 == .discard || $0 == .start }
            #expect(order == [.discard, .start])
            do {
                let found = try await world.stores.workouts.workout(id: first.id)
                #expect(found?.id == nil, "a discarded workout reaches no history")
            }
        }
    }
}
