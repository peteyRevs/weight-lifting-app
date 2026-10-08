@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, criteria 1 to 4: the launcher's lifecycle, one test for each row L1 to L9, L13, L14 and L17 of
/// the notes' table. On the fake session over the seeded in-memory stores. The rows that need a store to
/// refuse or a call to be held are `WorkoutLauncherFailureTests`'.
@MainActor
@Suite("WorkoutLauncher", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutLauncherTests {
    typealias Scene = WorkoutScene

    @Test("L1. Start with nothing live builds that day's workout, starts it once and opens the cover")
    func start_nothingLive_startsTheDayAndOpensTheCover() async throws {
        let scene = try Scene.onFake()
        let lowerA = try Scene.source(day: 1)
        #expect(scene.launcher.phase == .idle)
        #expect(scene.launcher.request == nil)

        scene.launcher.start(lowerA)
        #expect(scene.launcher.phase == .working)
        #expect(scene.launcher.request == WorkoutLaunchRequest(number: 1, job: .start(lowerA)))
        await scene.launcher.run()

        #expect(scene.launcher.phase == .cover)
        let live = try #require(try await scene.session.current())
        #expect(live.source == lowerA)
        #expect(live.name == "Lower A — Squat focus")
        #expect(live.startedAt == Fixtures.now)
        #expect(live.doneSets == 0)
        #expect(await scene.asked() == [.started(live.id)])
    }

    @Test("L2. Start for the day whose workout is live opens the cover on it, and never asks the use case")
    func start_sameDayLive_opensTheCoverWithoutTheUseCase() async throws {
        let running = try WorkoutPreview.logged(6, in: Fixtures.seedSession())
        let scene = try Scene.onFake(live: running)
        try await scene.ask { try $0.start(Scene.source(day: 0)) }

        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
        // `StartWorkoutUseCase.start` begins by reading the active program: no such read was made.
        #expect(await scene.probe.calls == [])
    }

    @Test(
        "L3. A live workout whose day was since deleted or emptied in the program is still shown (criterion 3)",
        arguments: [true, false]
    )
    func start_sameDayLive_dayGoneFromTheProgram_stillOpens(deleted: Bool) async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        try await scene.take(day: 0, out: deleted)

        try await scene.ask { try $0.start(Scene.source(day: 0)) }
        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.holds(running))
        #expect(await scene.probe.calls == [])

        // Control: with nothing live, the same request does reach the use case, which refuses that day.
        let empty = try Scene.onFake()
        try await empty.take(day: 0, out: deleted)
        try await empty.ask { try $0.start(Scene.source(day: 0)) }
        #expect(empty.launcher.phase == .failed(.notStarted(deleted ? .dayNotInProgram : .emptyDay)))
    }

    @Test("L4. Resume with a workout live opens the cover, and asks neither the use case nor the session to change")
    func resume_live_opensTheCover() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        await scene.ask { $0.resume() }
        #expect(scene.launcher.phase == .cover)
        #expect(scene.launcher.request == WorkoutLaunchRequest(number: 1, job: .resume))
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
        #expect(await scene.probe.calls == [])
    }

    @Test("L5. Resume with nothing live shows nothing")
    func resume_nothingLive_staysIdle() async throws {
        let scene = try Scene.onFake()
        await scene.ask { $0.resume() }
        #expect(scene.launcher.phase == .idle)
        #expect(try await scene.session.current()?.id == nil)
        #expect(await scene.asked() == [])
    }

    @Test("L17. A second request before the first is answered is dropped, and so is one made while the cover is up")
    func secondRequest_whileWorkingOrCovered_isDropped() async throws {
        let scene = try Scene.onFake()
        let upperA = try Scene.source(day: 0)
        scene.launcher.start(upperA)
        try scene.launcher.start(Scene.source(day: 1))
        scene.launcher.resume()
        scene.launcher.send(.resumeLive)
        #expect(scene.launcher.request == WorkoutLaunchRequest(number: 1, job: .start(upperA)))

        await scene.launcher.run()
        #expect(scene.launcher.phase == .cover)
        try scene.launcher.start(Scene.source(day: 1))
        scene.launcher.resume()
        try scene.launcher.send(.replaceLive(Scene.source(day: 1)))
        await scene.launcher.run()
        #expect(scene.launcher.phase == .cover)
        #expect(scene.launcher.request == WorkoutLaunchRequest(number: 1, job: .start(upperA)))
        #expect(await scene.asked().count == 1, "one workout was started, once")
    }

    @Test("The cover closing, a failure dismissed and a dialog cancelled each change only their own phase")
    func send_onlyActsOnItsOwnPhase() async throws {
        let scene = try Scene.onFake(live: Fixtures.seedSession())
        await scene.ask { $0.resume() }
        scene.launcher.send(.cancelConflict)
        scene.launcher.send(.dismissFailure)
        #expect(scene.launcher.phase == .cover)
        scene.launcher.send(.coverClosed)
        #expect(scene.launcher.phase == .idle)

        // After the cover closed (a minimize), the same workout opens again as it is.
        await scene.ask { $0.resume() }
        #expect(scene.launcher.phase == .cover)
        #expect(scene.launcher.request?.number == 2)

        scene.launcher.send(.coverClosed)
        try await scene.ask { try $0.start(Scene.source(day: 1)) }
        scene.launcher.send(.coverClosed)
        scene.launcher.send(.dismissFailure)
        #expect(try scene.launcher.phase == .conflict(Scene.source(day: 1)))
    }

    @Test("Running with nothing asked, or twice for one request, does nothing more")
    func run_withoutARequest_orAgain_doesNothing() async throws {
        let scene = try Scene.onFake()
        await scene.launcher.run()
        #expect(scene.launcher.phase == .idle)
        try await scene.ask { try $0.start(Scene.source(day: 0)) }
        await scene.launcher.run()
        #expect(await scene.asked().count == 1)
    }

    #if DEBUG
        @Test("The Debug menu's sample: with no active program it saves the seed program and starts its first day")
        func startSample_noProgram_savesTheSeedProgramAndStarts() async throws {
            let scene = try Scene.onFake()
            try await scene.stores.programs.delete(Fixtures.programID)
            #expect(try await scene.stores.programs.active()?.id == nil)

            await scene.ask { $0.startSample() }
            #expect(scene.launcher.phase == .cover)
            let program = try #require(try await scene.stores.programs.active())
            let isTheSeed = try program == Fixtures.seedProgram()
            #expect(isTheSeed)
            let first = try await scene.session.current()
            let firstDay = WorkoutSource(programID: program.id, weekIndex: 0, dayTemplateID: program.days[0].id)
            #expect(first?.source == firstDay)

            // Asked again it shows the same workout, and after a discard it starts one under a new id.
            scene.launcher.send(.coverClosed)
            await scene.ask { $0.startSample() }
            #expect(try await scene.session.current()?.id == first?.id)
            scene.launcher.send(.coverClosed)
            try await scene.fake?.discard(endedAt: Fixtures.now)
            await scene.ask { $0.startSample() }
            let second = try await scene.session.current()
            #expect(second?.source == first?.source)
            #expect(second?.id != first?.id)
        }
    #endif
}
