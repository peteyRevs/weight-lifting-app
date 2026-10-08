@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Rows L3 and L29, and requests that overlap.
extension WorkoutResumeAdversarialTests {
    @Test(
        "L3: a session that refuses the start starts nothing, says so, and the next try works",
        arguments: World.Kind.allCases
    )
    func start_sessionRefuses_isToldAndCanRetry(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await world.session.fail(.start)
            await rig.start(world.source(day: 0))
            #expect(rig.phase == .failed(.notStarted(.other)), "\(rig.phase)")
            let alert = WorkoutPresentation.alert(for: .notStarted(.other))
            #expect(alert.title == "Couldn't start this workout")
            #expect(alert.message == "Nothing was changed. Try again.")
            let live = try await world.live()
            #expect(live?.id == nil)
            await rig.answer(.dismissFailure)
            await rig.start(world.source(day: 0))
            #expect(rig.phase == .cover)
            #expect(rig.shown?.source == world.source(day: 0))
        }
    }

    @Test(
        "L3: a start whose answer is lost opens the cover on the workout that is live",
        arguments: World.Kind.allCases
    )
    func start_answerLost_showsTheWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await world.session.fail(.start, afterwards: true)
            await rig.start(world.source(day: 0))
            let live = try #require(try await world.live())
            #expect(rig.phase == .cover, "\(rig.phase)")
            #expect(rig.shown?.id == live.id)
        }
    }

    @Test("L3: a program store that throws starts nothing and says nothing was changed", arguments: World.Kind.allCases)
    func start_programStoreThrows_isTold(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await world.launcherStores.fail(.activeProgram)
            await rig.start(world.source(day: 0))
            #expect(rig.phase == .failed(.notStarted(.other)), "\(rig.phase)")
            let live = try await world.live()
            #expect(live?.id == nil)
        }
    }

    @Test(
        "A start when the session cannot be read at all is told, and says nothing false about the workout",
        arguments: World.Kind.allCases
    )
    func start_sessionUnreadable_liveWorkoutIsNotLost(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            await world.session.fail(.current, times: 10)
            await rig.start(world.source(day: 0))
            guard case .failed = rig.phase else {
                Issue.record("a session that cannot be read was not reported: \(rig.phase)")
                return
            }
            #expect(await world.session.count(.start) == 0)
            #expect(await world.session.count(.discard) == 0)
            await world.session.heal()
            #expect(try await unchanged(world.live(), first))
            await rig.answer(.dismissFailure)
            await rig.start(world.source(day: 0))
            #expect(rig.shown?.id == first.id)
        }
    }

    @Test("L29: resume when the session cannot be read is told; the workout stays", arguments: World.Kind.allCases)
    func resume_sessionUnreadable_isTold(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let first = try await world.begin(day: 0)
            let rig = AdversarialRig()
            await world.session.fail(.current, times: 10)
            await rig.resume()
            #expect(rig.phase == .failed(.notOpened), "\(rig.phase)")
            await world.session.heal()
            #expect(try await unchanged(world.live(), first))
        }
    }

    @Test(
        "Two requests at once, and a request while a start is in flight, start one workout",
        arguments: World.Kind.allCases
    )
    func overlappingRequests_startOne(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await world.session.hold(.start)
            rig.launcher.start(world.source(day: 0))
            rig.launcher.start(world.source(day: 1))
            let first = Task { await rig.launcher.run() }
            let second = Task { await rig.launcher.run() }
            await world.session.waitUntilHeld()
            rig.launcher.start(world.source(day: 2))
            rig.launcher.resume()
            await rig.launcher.run()
            #expect(rig.phase == .working)
            await world.session.release()
            await first.value
            await second.value
            await rig.settle()
            #expect(await world.session.count(.start) == 1)
            let live = try #require(try await world.live())
            #expect(live.source == world.source(day: 0), "the first request is the one answered")
            #expect(rig.shown?.id == live.id)
            #expect(rig.covers == 1)
        }
    }

    @Test(
        "A request whose task is cancelled while the start runs loses no workout: it is live and reachable",
        arguments: World.Kind.allCases
    )
    func cancelledRequest_losesNoWorkout(kind: World.Kind) async throws {
        try await World.run(kind) { world in
            let rig = AdversarialRig()
            await world.session.hold(.start)
            rig.launcher.start(world.source(day: 0))
            let running = Task { await rig.launcher.run() }
            await world.session.waitUntilHeld()
            running.cancel()
            await world.session.release()
            await running.value
            await rig.settle()
            let live = try #require(try await world.live(), "the host completes a start whose caller was cancelled")
            #expect(rig.phase == .cover || rig.phase == .idle, "\(rig.phase)")
            if rig.phase == .idle {
                await rig.start(world.source(day: 0))
            }
            #expect(rig.shown?.id == live.id)
            #expect(await world.session.count(.start) == 1)
        }
    }
}
