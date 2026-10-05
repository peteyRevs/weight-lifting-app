@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2 adversarial round 1, criterion 4's last sentence: a second tap while a save is in flight, or after it
/// succeeded, saves nothing more. Every tap the screen can send is thrown at a save held at each of its steps.
@Suite("Adversarial F08 S2 · one program, however the taps fall", .timeLimit(.minutes(1)))
struct OnboardingSaveOnceAdversarialTests {
    /// Where a save is held: reading the settings, reading the catalog, or inside the repository's save.
    nonisolated enum Stage: String, CaseIterable, Sendable {
        case settings, catalog, write

        @MainActor
        func script(in scene: AdversarialScene) -> CallScript {
            switch self {
            case .settings: scene.settings.script
            case .catalog: scene.exercises.script
            case .write: scene.programs.script
            }
        }
    }

    /// Everything a control can send.
    nonisolated static let everyAction: [OnboardingAction] = [
        .startTraining, .skipSetup, .retry, .back, .advance, .pickGoal(.strength), .pickDays(.three),
        .startTraining, .skipSetup
    ]

    @Test("A double tap on Start training makes one attempt and one program")
    func startTraining_tappedTwiceAtOnce_savesOne() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .strength, days: .six)
        scene.store.send(.startTraining)
        let attempt = scene.store.attempt
        scene.store.send(.startTraining)
        #expect(scene.store.attempt == attempt)
        await scene.runSave()
        await scene.runSave()
        try await scene.expectOneProgram(goal: .strength, days: .six)
    }

    @Test("While a save is held, no tap makes an attempt, moves a step or changes a pick", arguments: Stage.allCases)
    func save_inFlight_noTapAnswers(_ stage: Stage) async throws {
        let scene = try AdversarialScene(.seeded())
        await scene.store.loadUnits()
        scene.walk(goal: .hypertrophy, days: .three)
        let hold = Checkpoint()
        stage.script(in: scene).next(.hold(hold))
        scene.store.send(.startTraining)
        let attempt = try #require(scene.store.attempt)
        let task = Task { await scene.runSave() }
        await hold.arrivals()
        let before = scene.store.state
        for action in Self.everyAction {
            scene.store.send(action)
            await scene.runSave()
        }
        #expect(scene.store.attempt == attempt)
        #expect(scene.store.state == before)
        #expect(!scene.store.model.canProceed)
        #expect(!scene.store.model.canEdit)
        hold.open()
        await task.value
        try await scene.expectOneProgram(goal: .hypertrophy, days: .three)
    }

    @Test("After the program is saved nothing answers, and a run of the task saves nothing more")
    func save_succeeded_noTapAnswers() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .consistency, days: .five)
        await scene.tap(.startTraining)
        let after = scene.store.state
        let attempt = scene.store.attempt
        for action in Self.everyAction {
            await scene.tap(action)
            await scene.runSave()
        }
        #expect(scene.store.state == after)
        #expect(scene.store.attempt == attempt)
        #expect(!scene.store.model.canProceed)
        #expect(scene.store.model.error == nil)
        try await scene.expectOneProgram(goal: .consistency, days: .five)
    }

    @Test("Skip setup tapped during a save of the picks changes nothing: the picks' program is the one saved")
    func skipSetup_duringASaveOfThePicks_savesThePicks() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .strength, days: .six)
        let hold = Checkpoint()
        scene.programs.script.next(.hold(hold))
        scene.store.send(.startTraining)
        let task = Task { await scene.runSave() }
        await hold.arrivals()
        await scene.tap(.skipSetup)
        hold.open()
        await task.value
        await scene.tap(.skipSetup)
        try await scene.expectOneProgram(goal: .strength, days: .six)
    }

    @Test("Start training tapped during a skip changes nothing: the default program is the one saved")
    func startTraining_duringASkip_savesTheDefault() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .strength, days: .six)
        let hold = Checkpoint()
        scene.exercises.script.next(.hold(hold))
        scene.store.send(.skipSetup)
        let task = Task { await scene.runSave() }
        await hold.arrivals()
        await scene.tap(.startTraining)
        hold.open()
        await task.value
        await scene.tap(.startTraining)
        try await scene.expectOneProgram(goal: .both, days: .four)
    }
}

/// The view going away mid-save: its task is cancelled at each step of the save.
extension OnboardingSaveOnceAdversarialTests {
    @Test("A save cancelled before its write saves nothing, and the same tap then saves one", arguments: [
        Stage.settings, .catalog
    ])
    func save_cancelledBeforeTheWrite_savesNothingAndAnswersAgain(_ stage: Stage) async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .both, days: .five)
        let hold = Checkpoint()
        stage.script(in: scene).next(.hold(hold))
        scene.store.send(.startTraining)
        let task = Task { await scene.runSave() }
        await hold.arrivals()
        task.cancel()
        hold.open()
        await task.value
        #expect(
            scene.programs.offered.isEmpty,
            "the store's own promise: cancelled before the write, it writes nothing"
        )
        // The view comes back: its task runs again with the attempt it had, and the lifter taps what is there.
        await scene.runSave()
        #expect(!scene.store.state.phase.isSaving)
        #expect(scene.store.model.canProceed)
        await scene.tap(scene.store.model.primary.action)
        try await scene.expectOneProgram(goal: .both, days: .five)
    }

    @Test("A save cancelled during a write that still lands is saved: no later tap writes a second program")
    func save_cancelledDuringAWriteThatLands_staysSaved() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .hypertrophy, days: .four)
        let hold = Checkpoint()
        scene.programs.script.next(.hold(hold))
        scene.store.send(.startTraining)
        let task = Task { await scene.runSave() }
        await hold.arrivals()
        task.cancel()
        hold.open()
        await task.value
        await scene.runSave()
        for action in Self.everyAction {
            await scene.tap(action)
        }
        try await scene.expectOneProgram(goal: .hypertrophy, days: .four)
        #expect(!scene.store.model.canProceed)
        #expect(scene.store.model.error == nil)
    }

    @Test("A write that gives up on cancellation leaves nothing saved and a screen that answers: then one program")
    func save_cancelledDuringAWriteThatGivesUp_answersAgain() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .strength, days: .three)
        let hold = Checkpoint()
        scene.programs.script.next(.hold(hold, then: .honourCancellation))
        scene.store.send(.startTraining)
        let task = Task { await scene.runSave() }
        await hold.arrivals()
        task.cancel()
        hold.open()
        await task.value
        #expect(scene.programs.saved.isEmpty)
        #expect(try await scene.stores.programs.active() == nil)
        await scene.runSave()
        #expect(!scene.store.state.phase.isSaving)
        #expect(scene.store.model.canProceed)
        await scene.tap(scene.store.model.primary.action)
        try await scene.expectOneProgram(goal: .strength, days: .three, offered: 2)
    }

    @Test("The view returns while its cancelled save is still held: the two runs together save at most one program")
    func save_cancelledAndRunAgainWhileHeld_savesAtMostOne() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .consistency, days: .six)
        let hold = Checkpoint()
        scene.settings.script.next(.hold(hold))
        scene.store.send(.startTraining)
        let first = Task { await scene.runSave() }
        await hold.arrivals()
        first.cancel()
        let second = Task { await scene.runSave() }
        await second.value
        hold.open()
        await first.value
        #expect(scene.programs.saved.count <= 1)
        if scene.programs.saved.isEmpty {
            #expect(scene.store.model.canProceed, "nothing is saved, so the screen must answer")
            await scene.tap(scene.store.model.primary.action)
        }
        try await scene.expectOneProgram(goal: .consistency, days: .six)
    }
}
