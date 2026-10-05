@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2 adversarial round 1, criterion 7: each of the four steps of a save failing, the sentence the screen
/// then shows, and "Retry", which first awaits the root's `prepareRetry` and then tries again with the same picks.
@Suite("Adversarial F08 S2 · a save that fails, and the retry", .timeLimit(.minutes(1)))
struct OnboardingFailureAdversarialTests {
    /// The step of a save that fails.
    nonisolated enum Fault: String, CaseIterable, Sendable {
        case settings, catalog, generator, write

        /// A scene whose next save fails at this step. The generator fails on a catalog that was never seeded
        /// (product decision #28), which the scene's retry step then seeds, as the launch's seed step would.
        @MainActor
        func scene() async throws -> AdversarialScene {
            let scene = try AdversarialScene(self == .generator ? .unseeded : .seeded())
            await scene.store.loadUnits()
            switch self {
            case .settings: scene.settings.script.next(.fail(rawValue))
            case .catalog: scene.exercises.script.next(.fail(rawValue))
            case .write: scene.programs.script.next(.fail(rawValue))
            case .generator:
                let exercises = scene.stores.exercises
                scene.onPrepare = {
                    // A seed that fails here leaves the catalog empty, and the retry then fails the test.
                    try? await exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
                }
            }
            return scene
        }

        /// How many programs reach the repository before one is stored.
        var offered: Int {
            self == .write ? 2 : 1
        }
    }

    /// The failure state as criterion 7 words it, with the picks still shown.
    static func expectFailureShown(
        _ scene: AdversarialScene,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let model = scene.store.model
        #expect(model.error == BriefCopy.saveFailed, sourceLocation: sourceLocation)
        #expect(model.primary.title == BriefCopy.retry, sourceLocation: sourceLocation)
        #expect(model.primary.action == .retry, sourceLocation: sourceLocation)
        #expect(model.canProceed, "Retry answers", sourceLocation: sourceLocation)
        #expect(scene.programs.saved.isEmpty, sourceLocation: sourceLocation)
        #expect(try await scene.stores.programs.active() == nil, sourceLocation: sourceLocation)
    }

    @Test(
        "Each failing step shows the sentence and Retry, saves nothing and prepares nothing",
        arguments: Fault.allCases
    )
    func startTraining_stepFails_showsTheSentenceAndSavesNothing(_ fault: Fault) async throws {
        let scene = try await fault.scene()
        scene.walk(goal: .strength, days: .five)
        await scene.tap(.startTraining)
        try await Self.expectFailureShown(scene)
        #expect(scene.journal.count(of: "prepare.start") == 0, "the first attempt does not prepare")
        #expect(scene.store.state.step == .program)
        #expect(scene.store.state.goal == .strength)
        #expect(scene.store.state.days == .five)
        #expect(scene.store.model.title == BriefCopy.programTitle)
        #expect(scene.store.model.body == BriefCopy.programBody(.five, .lb))
    }

    @Test(
        "Retry awaits prepareRetry once, before it reads or writes anything, then saves the picks' program",
        arguments: Fault.allCases
    )
    func retry_afterAFailure_preparesFirstThenSavesThePicks(_ fault: Fault) async throws {
        let scene = try await fault.scene()
        scene.walk(goal: .strength, days: .five)
        await scene.tap(.startTraining)
        let failed = scene.journal.all.count
        await scene.tap(.retry)
        let retry = Array(scene.journal.all.dropFirst(failed))
        #expect(Array(retry.prefix(2)) == ["prepare.start", "prepare.end"], "\(retry)")
        #expect(retry.count { $0 == "prepare.start" } == 1)
        #expect(retry.contains("programs.save"))
        try await scene.expectOneProgram(goal: .strength, days: .five, offered: fault.offered)
        #expect(scene.store.model.error == nil)
        #expect(!scene.store.model.canProceed)
        await scene.tap(.retry)
        #expect(scene.journal.count(of: "prepare.start") == 1, "nothing prepares after the program is saved")
    }

    @Test("A retry that fails again shows the sentence again; the third try saves one program, after three prepares")
    func retry_failsAgain_thenSucceeds() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.programs.script.next(.fail("first"), .fail("second"))
        scene.exercises.script.next(.pass, .pass, .fail("third"))
        scene.walk(goal: .hypertrophy, days: .six)
        await scene.tap(.startTraining)
        for expectedPrepares in 1 ... 3 {
            try await Self.expectFailureShown(scene)
            #expect(scene.store.state.goal == .hypertrophy)
            #expect(scene.store.state.days == .six)
            await scene.tap(.retry)
            #expect(scene.journal.count(of: "prepare.start") == expectedPrepares)
            #expect(scene.journal.count(of: "prepare.end") == expectedPrepares)
        }
        try await scene.expectOneProgram(goal: .hypertrophy, days: .six, offered: 3)
    }
}

/// A retry step that is slow or never returns, stores that changed since the failure, and "Skip setup" around a
/// failure.
extension OnboardingFailureAdversarialTests {
    @Test("While prepareRetry is slow nothing is read or written and no tap answers; then one program")
    func retry_prepareIsSlow_waitsForIt() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.programs.script.next(.fail("write"))
        scene.walk(goal: .both, days: .three)
        await scene.tap(.startTraining)
        let slow = Checkpoint()
        scene.onPrepare = { await slow.pass() }
        scene.store.send(.retry)
        let attempt = scene.store.attempt
        let task = Task { await scene.runSave() }
        await slow.arrivals()
        let during = scene.journal.all
        #expect(during.last == "prepare.start")
        for action in OnboardingSaveOnceAdversarialTests.everyAction {
            scene.store.send(action)
            await scene.runSave()
        }
        #expect(scene.store.attempt == attempt)
        #expect(scene.journal.all == during, "nothing runs while the retry step does")
        #expect(scene.programs.offered.count == 1)
        slow.open()
        await task.value
        #expect(scene.journal.count(of: "prepare.start") == 1)
        try await scene.expectOneProgram(goal: .both, days: .three, offered: 2)
    }

    @Test("A prepareRetry that never returns saves nothing; once its task is cancelled the screen answers again")
    func retry_prepareNeverReturnsUntilCancelled_savesNothingThenAnswers() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.exercises.script.next(.fail("catalog"))
        scene.walk(goal: .consistency, days: .four)
        await scene.tap(.startTraining)
        let stuck = Checkpoint()
        scene.onPrepare = { await stuck.pass() }
        scene.store.send(.retry)
        let task = Task { await scene.runSave() }
        await stuck.arrivals()
        #expect(scene.programs.offered.isEmpty)
        // The view goes away: only then does the step give up, as a cancelled seed step would.
        task.cancel()
        stuck.open()
        await task.value
        #expect(scene.programs.offered.isEmpty, "cancelled before the write, the retry writes nothing")
        #expect(!scene.store.state.phase.isSaving)
        #expect(scene.store.model.canProceed)
        scene.onPrepare = {}
        await scene.tap(scene.store.model.primary.action)
        try await scene.expectOneProgram(goal: .consistency, days: .four)
    }

    @Test("The retry reads the stores again: a catalog seeded and a unit changed since the failure are the ones used")
    func retry_storesChangedSinceTheFailure_usesWhatIsStoredNow() async throws {
        let scene = AdversarialScene(.unseeded)
        scene.walk(goal: .strength, days: .six)
        await scene.tap(.startTraining)
        try await Self.expectFailureShown(scene)
        try await scene.stores.exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        try await scene.stores.settings.save(Fixtures.settingsKg)
        await scene.tap(.retry)
        try await scene.expectOneProgram(goal: .strength, days: .six)
        let bench = try #require(ExerciseCatalog.seed().first { $0.name == "Barbell Bench Press" })
        let slot = scene.programs.saved.flatMap(\.days).flatMap(\.slots).first { $0.exerciseID == bench.id }
        #expect(slot?.startLoad == bench.startLoad(in: .kg))
    }

    @Test(
        "A failed Skip setup shows the sentence where the lifter stands, and Retry saves the default",
        arguments: 0 ... 2
    )
    func skipSetup_fails_retrySavesTheDefault(advances: Int) async throws {
        let scene = try AdversarialScene(.seeded())
        scene.programs.script.next(.fail("write"))
        scene.store.send(.pickGoal(.hypertrophy))
        for _ in 0 ..< advances {
            scene.store.send(.advance)
        }
        await scene.tap(.skipSetup)
        try await Self.expectFailureShown(scene)
        #expect(scene.store.state.step.rawValue == advances, "a failure moves no step")
        #expect(scene.store.state.goal == .hypertrophy)
        await scene.tap(.retry)
        #expect(scene.journal.count(of: "prepare.start") == 1)
        try await scene.expectOneProgram(goal: .both, days: .four, offered: 2)
    }

    @Test("Skip setup after a failed Start training saves the default program, once")
    func skipSetup_afterAFailedStart_savesTheDefault() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.settings.script.next(.fail("settings"))
        scene.walk(goal: .strength, days: .six)
        await scene.tap(.startTraining)
        try await Self.expectFailureShown(scene)
        #expect(scene.store.model.skip.title == BriefCopy.skipSetup)
        #expect(scene.store.model.skip.action == .skipSetup)
        await scene.tap(.skipSetup)
        try await scene.expectOneProgram(goal: .both, days: .four)
        #expect(scene.store.model.error == nil)
    }

    @Test("Settings that cannot be read when the screen opens keep the default unit; the save then fails in view")
    func loadUnits_settingsUnreadable_keepsPoundsAndTheSaveFails() async throws {
        let scene = try AdversarialScene(.seeded(Fixtures.settingsKg))
        scene.settings.script.otherwise(.fail("settings"))
        await scene.store.loadUnits()
        scene.walk(goal: .both, days: .four)
        #expect(scene.store.model.body == BriefCopy.programBody(.four, .lb))
        #expect(scene.store.model.error == nil, "an unread unit is not a failed save")
        await scene.tap(.startTraining)
        try await Self.expectFailureShown(scene)
        #expect(scene.programs.offered.isEmpty)
    }
}
