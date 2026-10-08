@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, criterion 4 and the failures of criteria 1 and 2: rows L10 to L12, L15, L16, L18 and L19 of the
/// notes' table. Most run on the real host over probed in-memory stores, which can refuse a write or hold a
/// call where the fake cannot. After each, exactly one workout is live or none, and the launcher says which.
@MainActor
@Suite("WorkoutLauncher failures", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutLauncherFailureTests {
    typealias Scene = WorkoutScene

    /// Upper A live on the host, and the conflict dialog up for Lower A.
    struct Conflict {
        let scene: Scene
        let running: WorkoutState
        let asked: WorkoutSource

        @MainActor
        init() async throws {
            running = try Fixtures.seedSession()
            scene = try await Scene.onHost(live: running)
            asked = try Scene.source(day: 1)
            await scene.ask { [asked] in $0.start(asked) }
            #expect(scene.launcher.phase == .conflict(asked))
            await scene.probe.clearCalls()
        }
    }

    @Test("L10. \"Discard and start new\" whose discard fails starts nothing: the old workout is live, and it says so")
    func replace_discardFails_keepsTheOldWorkout_startsNothing() async throws {
        let conflict = try await Conflict()
        let (scene, running, lowerA) = (conflict.scene, conflict.running, conflict.asked)
        await scene.probe.fail(.append)
        await scene.ask { $0.send(.replaceLive(lowerA)) }

        #expect(scene.launcher.phase == .failed(.notReplaced(.liveKept)))
        #expect(try await scene.holds(running))
        // The one write that was tried is the discard's, which was refused: no start followed it.
        #expect(await scene.appends() == 1)
        #expect(try await scene.stores.events.uncompactedWorkoutIDs() == [running.id])
        let alert = WorkoutPresentation.alert(for: .notReplaced(.liveKept))
        #expect(alert.title == "Couldn't start the new workout")
        #expect(alert.message == "Your workout in progress was kept.")

        // "OK", then the same choice again, now that the store answers: one workout live, the new one.
        scene.launcher.send(.dismissFailure)
        #expect(scene.launcher.phase == .idle)
        await scene.ask { $0.send(.replaceLive(lowerA)) }
        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.session.current()?.source == lowerA)
    }

    @Test("L11. \"Discard and start new\" whose start fails after the discard leaves none live, and says so")
    func replace_startFailsAfterTheDiscard_leavesNoneLive() async throws {
        let conflict = try await Conflict()
        let (scene, running, lowerA) = (conflict.scene, conflict.running, conflict.asked)
        // The discard's log is being dropped: from here on the next write, the start's, is refused.
        await scene.probe.hold(.compact)
        scene.launcher.send(.replaceLive(lowerA))
        async let answered: Void = scene.launcher.run()
        try await scene.probe.waitUntilHeld()
        await scene.probe.fail(.append)
        await scene.probe.release()
        await answered

        #expect(scene.launcher.phase == .failed(.notReplaced(.nothingLive)))
        #expect(try await scene.session.current()?.id == nil)
        #expect(try await scene.stores.events.uncompactedWorkoutIDs() == [])
        #expect(try await scene.stores.workouts.workout(id: running.id)?.id == nil, "discarded, not saved")
        #expect(WorkoutPresentation.alert(for: .notReplaced(.nothingLive)).message
            == "Your workout in progress was discarded.")
    }

    @Test("L12. \"Discard and start new\" for a day that can no longer be built discards nothing")
    func replace_dayCannotBeBuilt_discardsNothing() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        let lowerA = try Scene.source(day: 1)
        await scene.ask { $0.start(lowerA) }
        try await scene.emptyDay(1)

        await scene.ask { $0.send(.replaceLive(lowerA)) }
        #expect(scene.launcher.phase == .failed(.notReplaced(.liveKept)))
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
    }

    @Test("L17. While a start is still running, a second run and a second request start nothing more")
    func start_stillRunning_secondRunAndRequestDoNothing() async throws {
        let scene = try await Scene.onHost()
        let upperA = try Scene.source(day: 0)
        await scene.probe.hold(.append)
        scene.launcher.start(upperA)
        async let first: Void = scene.launcher.run()
        try await scene.probe.waitUntilHeld()

        await scene.launcher.run()
        try scene.launcher.start(Scene.source(day: 1))
        #expect(scene.launcher.phase == .working)
        #expect(scene.launcher.request == WorkoutLaunchRequest(number: 1, job: .start(upperA)))

        await scene.probe.release()
        await first
        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.session.current()?.source == upperA)
        #expect(await scene.appends() == 1)
    }

    @Test("L18. A start that is still running when the view goes away is completed by the host, and is no failure")
    func start_viewGoesAwayWhileItRuns_isNoFailure() async throws {
        let scene = try await Scene.onHost()
        let upperA = try Scene.source(day: 0)
        await scene.probe.hold(.append)
        scene.launcher.start(upperA)
        let work = Task { await scene.launcher.run() }
        try await scene.probe.waitUntilHeld()
        work.cancel()
        await scene.probe.release()
        await work.value

        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.session.current()?.source == upperA)
        #expect(await scene.appends() == 1)
    }

    @Test("L18. A request cancelled before it changed anything leaves the launcher idle, and shows no failure")
    func request_cancelledBeforeItsAnswer_isIdle() async throws {
        let gate = Gate()
        let running = try Fixtures.seedSession()
        let scene = try Scene.on(GatedSession(base: FakeWorkoutSessionClient(live: running), gate: gate))
        scene.launcher.resume()
        let work = Task { await scene.launcher.run() }
        await gate.waitForArrival()
        work.cancel()
        await gate.open()
        await work.value
        #expect(scene.launcher.phase == .idle)

        // The same request, asked again once the view is back, is answered.
        await scene.ask { $0.resume() }
        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.holds(running))
    }

    @Test("L19. A start whose write went through and whose answer was lost opens the cover on that workout")
    func start_answerLost_opensTheWorkoutThatIsLive() async throws {
        let scene = try await Scene.onHost()
        let upperA = try Scene.source(day: 0)
        await scene.probe.fail(.append, afterStoring: true)
        await scene.ask { $0.start(upperA) }
        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.session.current()?.source == upperA)
        #expect(try await scene.stores.events.uncompactedWorkoutIDs().count == 1)
    }
}
