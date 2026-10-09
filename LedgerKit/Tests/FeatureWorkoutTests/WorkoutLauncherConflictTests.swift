@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, criterion 4 (the brief's criterion 2): the conflict with a workout that is already running, rows
/// L6 to L9, L13 and L14 of the notes' table. On the fake session, which records the order of what it was
/// asked. What happens when the discard or the start fails is `WorkoutLauncherFailureTests`'.
@MainActor
@Suite("WorkoutLauncher conflict", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutLauncherConflictTests {
    typealias Scene = WorkoutScene

    @Test("L6. Start for another day while a workout is live asks, and changes nothing")
    func start_anotherDayLive_asks() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let lowerA = try Scene.source(day: 1)
        await scene.ask { $0.start(lowerA) }
        #expect(scene.launcher.phase == .conflict(lowerA))
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
    }

    @Test("L7. The conflict's \"Resume it\" opens the cover on the live workout")
    func conflict_resume_opensTheLiveWorkout() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        try await scene.ask { try $0.start(Scene.source(day: 1)) }
        await scene.ask { $0.send(.resumeLive) }
        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
    }

    @Test("L8. \"Discard and start new\" discards the live workout, then starts the day that was asked for")
    func conflict_replace_discardsThenStarts() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let lowerA = try Scene.source(day: 1)
        await scene.ask { $0.start(lowerA) }
        await scene.ask { $0.send(.replaceLive(lowerA)) }

        #expect(scene.launcher.phase == .cover)
        let live = try #require(try await scene.session.current())
        #expect(live.source == lowerA)
        #expect(live.id != running.id)
        // In this order, and nothing else: the discard, at the moment the new workout starts, then the start.
        #expect(await scene.asked() == [.discarded(Fixtures.now), .started(live.id)])
        #expect(try await scene.stores.workouts.workout(id: running.id)?.id == nil, "the first is not in history")
    }

    @Test("L9. The conflict's \"Cancel\", or the dialog going away, leaves everything as it was")
    func conflict_cancel_changesNothing() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        try await scene.ask { try $0.start(Scene.source(day: 1)) }
        let asked = scene.launcher.request
        scene.launcher.send(.cancelConflict)
        #expect(scene.launcher.phase == .idle)
        #expect(scene.launcher.request == asked, "a cancel is no work")
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
    }

    @Test("L13. The live workout ends elsewhere while the dialog shows: \"Discard and start new\" still starts")
    func conflict_liveEndsMeanwhile_replaceStarts() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        let lowerA = try Scene.source(day: 1)
        await scene.ask { $0.start(lowerA) }
        try await scene.fake?.discard(endedAt: Fixtures.now)

        await scene.ask { $0.send(.replaceLive(lowerA)) }
        #expect(scene.launcher.phase == .cover)
        let live = try #require(try await scene.session.current())
        #expect(live.source == lowerA)
        // The one discard is the one made elsewhere: the launcher discarded nothing.
        #expect(await scene.asked() == [.discarded(Fixtures.now), .started(live.id)])
    }

    @Test("L14. The live workout ends elsewhere while the dialog shows: \"Resume it\" shows nothing")
    func conflict_liveEndsMeanwhile_resumeShowsNothing() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        try await scene.ask { try $0.start(Scene.source(day: 1)) }
        try await scene.fake?.discard(endedAt: Fixtures.now)
        await scene.ask { $0.send(.resumeLive) }
        #expect(scene.launcher.phase == .idle)
        #expect(try await scene.session.current()?.id == nil)
    }
}
