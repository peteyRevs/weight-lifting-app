@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S4, the failures of criteria 1 and 2: a start or a resume that is refused, rows L15 and L16 of the
/// notes' table. Each says why, and changes nothing: what was live still is.
@MainActor
@Suite("WorkoutLauncher refusals", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutLauncherRefusalTests {
    typealias Scene = WorkoutScene

    @Test("L15. A start the use case refuses says why, one reason each, and changes nothing")
    func start_refused_saysWhy() async throws {
        let scene = try Scene.onFake()
        try await scene.emptyDay(2)
        let stranger = WorkoutSource(
            programID: Fixtures.programID,
            weekIndex: WorkoutScene.week,
            dayTemplateID: DayTemplateID(Fixtures.uuid(77))
        )
        let otherProgram = WorkoutSource(
            programID: ProgramID(Fixtures.uuid(78)),
            weekIndex: WorkoutScene.week,
            dayTemplateID: stranger.dayTemplateID
        )
        var phases: [WorkoutLaunchPhase] = []
        for source in try [Scene.source(day: 2), stranger, otherProgram, Scene.source(day: 0, week: 99)] {
            await scene.ask { $0.start(source) }
            phases.append(scene.launcher.phase)
            scene.launcher.send(.dismissFailure)
        }
        await scene.probe.fail(.activeProgram)
        try await scene.ask { try $0.start(Scene.source(day: 0)) }
        phases.append(scene.launcher.phase)

        #expect(phases == [
            .failed(.notStarted(.emptyDay)), .failed(.notStarted(.dayNotInProgram)),
            .failed(.notStarted(.dayNotInProgram)), .failed(.notStarted(.blockEnded)), .failed(.notStarted(.other))
        ])
        #expect(try await scene.session.current()?.id == nil)
        #expect(await scene.asked() == [])
    }

    @Test("L15. A refused start for another day leaves the live workout as it was")
    func start_refused_whileAnotherIsLive_keepsIt() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.onFake(live: running)
        try await scene.emptyDay(1)
        try await scene.ask { try $0.start(Scene.source(day: 1)) }
        #expect(scene.launcher.phase == .failed(.notStarted(.emptyDay)))
        #expect(try await scene.holds(running))
        #expect(await scene.asked() == [])
    }

    @Test("L15. A start the store refuses starts nothing and leaves nothing live")
    func start_storeRefusesTheWrite_startsNothing() async throws {
        let scene = try await Scene.onHost()
        await scene.probe.fail(.append)
        try await scene.ask { try $0.start(Scene.source(day: 0)) }
        #expect(scene.launcher.phase == .failed(.notStarted(.other)))
        #expect(try await scene.session.current()?.id == nil)
        #expect(try await scene.stores.events.uncompactedWorkoutIDs() == [])
    }

    @Test("L16. A resume or a start that cannot read the session opens nothing and says so")
    func sessionCannotBeRead_opensNothing() async throws {
        let scene = try Scene.on(EndedSession())
        await scene.ask { $0.resume() }
        #expect(scene.launcher.phase == .failed(.notOpened))
        let alert = WorkoutPresentation.alert(for: .notOpened)
        #expect(alert.title == "Couldn't open this workout")
        #expect(alert.message == "Try again.")

        scene.launcher.send(.dismissFailure)
        // Criterion 16: the session could not be read again, so the line does not say that nothing changed.
        try await scene.ask { try $0.start(Scene.source(day: 0)) }
        #expect(scene.launcher.phase == .failed(.notStarted(.unknown)))
        #expect(WorkoutPresentation.alert(for: .notStarted(.unknown)).message == "Try again.")
        scene.launcher.send(.dismissFailure)
        try await scene.ask { try $0.send(.replaceLive(Scene.source(day: 0))) }
        #expect(scene.launcher.phase == .failed(.notReplaced(.unknown)))
    }

    @Test("A CancellationError from the session on a task nobody cancelled is a failure like any other")
    func cancellationError_onATaskNobodyCancelled_isAFailure() async throws {
        let scene = try Scene.on(EndedSession(error: CancellationError()))
        await scene.ask { $0.resume() }
        #expect(scene.launcher.phase == .failed(.notOpened))
    }

    @Test("A resume whose read failed and whose second read finds the workout opens the cover on it")
    func resume_firstReadFails_secondFindsTheWorkout_opensTheCover() async throws {
        let running = try Fixtures.seedSession()
        let scene = try Scene.on(FlakySession(base: FakeWorkoutSessionClient(live: running)))
        await scene.ask { $0.resume() }
        #expect(scene.launcher.phase == .cover)
        #expect(try await scene.holds(running))
    }
}
