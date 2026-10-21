@testable import FeatureOnboarding
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import OSLog
import Testing

/// F08 S2, criterion 7 as revised after round 1 (standards §8): a failure is logged under the module's own
/// category, and a cancelled task is not a failure and is not logged as one. Every scene here logs for real, and
/// the process's own log is read back through `OSLogStore`. The planted failures carry a word of their own, so
/// a line is found by what it says.
///
/// One read of the log takes two to nine seconds, so the scenes share one read, and the suite runs in the
/// nightly lane only (testing-strategy §6: a slow test inside a PR target).
@Suite("Adversarial F08 S2 · a failure is logged", .timeLimit(.minutes(1)))
struct OnboardingLoggingAdversarialTests {
    typealias Fault = OnboardingFailureAdversarialTests.Fault

    /// One line this process logged under the app's subsystem.
    nonisolated struct Line: Sendable, CustomStringConvertible {
        let category: String
        let level: OSLogEntryLog.Level
        let text: String

        var description: String {
            "[\(category), level \(level.rawValue)] \(text)"
        }
    }

    /// What the scenes left in the log: the lines of the failures and cancellations, then, after a marker, those
    /// of the one scene whose store throws `CancellationError` on a task nobody cancelled.
    nonisolated struct Logged: Sendable {
        let main: [Line]
        let spurious: [Line]
    }

    /// The category the scenes' injected logger has: the module must not log under it.
    nonisolated static let injected = "adversarial-f08s2"
    /// Standards §8, as revised: `logger.category("onboarding")`.
    nonisolated static let modules = "onboarding"
    nonisolated static let marker = "f08s2-marker-spurious"
    nonisolated static let runsSlowTests = AdversarialLane.isNightly

    /// Every line of this process under the app's subsystem, oldest first.
    nonisolated static func lines() throws -> [Line] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@", LedgerLogger.subsystem)
        return try store.getEntries(matching: predicate)
            .compactMap { $0 as? OSLogEntryLog }
            .map { Line(category: $0.category, level: $0.level, text: $0.composedMessage) }
    }

    /// A scene that logs for real, whose next save fails at `fault` with `word` in the failure. The generator
    /// fails on a catalog that lacks one exercise no other suite leaves out, so its line is this scene's alone.
    static func scene(_ fault: Fault, word: String) throws -> AdversarialScene {
        var setup = try AdversarialScene.Setup.seeded()
        if fault == .generator {
            setup.seed.catalog.removeAll { $0.name == "Seated Leg Curl" }
        }
        setup.logger = LedgerLogger(category: injected)
        let scene = AdversarialScene(setup)
        switch fault {
        case .settings: scene.settings.script.next(.fail(word))
        case .catalog: scene.exercises.script.next(.fail(word))
        case .write: scene.programs.script.next(.fail(word))
        case .generator: break
        }
        return scene
    }

    /// A scene that logs for real and in which nothing is planted.
    static func quietScene() throws -> AdversarialScene {
        var setup = try AdversarialScene.Setup.seeded()
        setup.logger = LedgerLogger(category: injected)
        return AdversarialScene(setup)
    }

    /// A save that fails once at each step it can, a retry that fails again, and an unreadable unit when the
    /// screen opens: six failures, seven lines.
    static func runEveryFailure() async throws {
        for fault in [Fault.settings, .catalog, .write] {
            let scene = try scene(fault, word: "f08s2-save-\(fault.rawValue)")
            scene.walk(goal: .strength, days: .six)
            await scene.tap(.startTraining)
            #expect(scene.store.model.error == BriefCopy.saveFailed)
        }
        let retried = try scene(.write, word: "f08s2-retry")
        retried.programs.script.next(.fail("f08s2-retry"))
        await retried.tap(.skipSetup)
        await retried.tap(.retry)
        await retried.tap(.retry)
        #expect(retried.programs.saved.count == 1)
        let unseeded = try scene(.generator, word: "")
        await unseeded.tap(.skipSetup)
        #expect(unseeded.store.model.error == BriefCopy.saveFailed)
        let unread = try scene(.settings, word: "f08s2-units")
        await unread.store.loadUnits()
        #expect(unread.store.model.error == nil)
    }

    /// The view going away: the unit read cancelled mid-load, and a save cancelled at each of its reads and in
    /// its write. None is a failure, so none leaves a line.
    static func runEveryCancellation() async throws {
        let midLoad = try quietScene()
        let loading = Checkpoint()
        midLoad.settings.script.next(.hold(loading, then: .honourCancellation))
        let load = Task { await midLoad.store.loadUnits() }
        await loading.arrivals()
        load.cancel()
        loading.open()
        await load.value
        for stage in OnboardingSaveOnceAdversarialTests.Stage.allCases {
            let scene = try quietScene()
            let hold = Checkpoint()
            stage.script(in: scene).next(.hold(hold, then: .honourCancellation))
            scene.store.send(.skipSetup)
            let save = Task { await scene.runSave() }
            await hold.arrivals()
            save.cancel()
            hold.open()
            await save.value
            #expect(scene.programs.saved.isEmpty, "\(stage)")
            #expect(scene.store.model.error == nil, "a cancelled save is not shown as a failure. \(stage)")
        }
    }

    /// A store that throws `CancellationError` although nobody cancelled the task: the save fails in view.
    static func runTheSpuriousCancellation() async throws {
        let scene = try quietScene()
        scene.programs.script.next(CallPlan(outcome: .cancellation))
        await scene.tap(.skipSetup)
        #expect(scene.store.model.error == BriefCopy.saveFailed, "control: the screen shows this as a failure")
        #expect(scene.programs.saved.isEmpty)
    }

    /// The lines the scenes left, read once for the suite's tests.
    static let logged = Task { () -> Logged in
        let before = try lines().count
        try await runEveryFailure()
        try await runEveryCancellation()
        Logger(subsystem: LedgerLogger.subsystem, category: injected).error("\(marker, privacy: .public)")
        try await runTheSpuriousCancellation()
        let ours = try Array(lines().dropFirst(before)).filter { line in
            ["f08s2-", "Seated Leg Curl", "CancellationError"].contains { line.text.contains($0) }
                || line.category == injected
        }
        let cut = ours.firstIndex { $0.text == marker } ?? ours.endIndex
        return Logged(main: Array(ours[..<cut]), spurious: Array(ours[cut...].dropFirst()))
    }

    @Test(
        "Each failed attempt logs one line at error level or above; the cancellations log none",
        .enabled(if: runsSlowTests)
    )
    func failures_everyStep_areLoggedOnce() async throws {
        let lines = try await Self.logged.value.main
        func count(_ word: String) -> Int {
            lines.count { $0.text.contains(word) }
        }
        #expect(count("f08s2-save-settings") == 1, "\(lines)")
        #expect(count("f08s2-save-catalog") == 1, "\(lines)")
        #expect(count("f08s2-save-write") == 1, "\(lines)")
        #expect(count("f08s2-retry") == 2, "one line for each failed attempt. \(lines)")
        #expect(count("f08s2-units") == 1, "the unreadable unit when the screen opens. \(lines)")
        #expect(count("Seated Leg Curl") == 1, "the exercise the generator missed. \(lines)")
        #expect(count("CancellationError") == 0, "criterion 7: a cancelled task is not logged as a failure. \(lines)")
        #expect(lines.count == 7, "\(lines)")
        #expect(lines.allSatisfy { $0.level == .error || $0.level == .fault }, "\(lines)")
        #expect(lines.allSatisfy { !$0.text.localizedCaseInsensitiveContains("ledger") }, "\(lines)")
    }

    @Test(
        "Every line is under the module's own category, whatever category the injected logger has",
        .enabled(if: runsSlowTests)
    )
    func failures_areLoggedUnderTheModulesCategory() async throws {
        // Standards §8: "a category per module"; a store logs through the injected logger under
        // `logger.category("onboarding")`. The scenes' injected logger has another category.
        let lines = try await Self.logged.value.main
        #expect(!lines.isEmpty)
        #expect(Set(lines.map(\.category)) == [Self.modules], "\(lines)")
    }

    @Test(
        "A failure the screen shows is logged, even when the store's error says cancellation and nobody cancelled",
        .enabled(if: runsSlowTests)
    )
    func shownFailure_ofAnUncancelledTask_isLogged() async throws {
        // Criterion 7: the screen shows the sentence "and the failure is logged". Only a cancelled task is no
        // failure. Here the task runs on and the screen shows the sentence, so one line is due.
        let lines = try await Self.logged.value.spurious
        #expect(lines.count == 1, "the screen showed a failure and the log has \(lines)")
        #expect(lines.allSatisfy { $0.category == Self.modules && $0.level == .error }, "\(lines)")
    }
}
