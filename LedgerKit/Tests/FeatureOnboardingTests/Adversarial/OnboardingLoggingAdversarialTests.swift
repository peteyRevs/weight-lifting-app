@testable import FeatureOnboarding
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import OSLog
import Testing

/// F08 S2 adversarial round 1, criterion 7's "the failure is logged" (standards §8: `os.Logger`, the app's
/// subsystem, never swallowed): every failing step leaves one line in the process's own log, read back through
/// `OSLogStore`. The planted failures carry a word of their own, so a line is found by what it says.
///
/// One read of the log takes two to nine seconds, so the suite is one test with one read, and it runs in the
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

    nonisolated static let category = "adversarial-f08s2"
    nonisolated static let runsSlowTests = AdversarialLane.isNightly

    /// Every line of this process under the app's subsystem, oldest first.
    nonisolated static func lines() throws -> [Line] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@", LedgerLogger.subsystem)
        return try store.getEntries(matching: predicate)
            .compactMap { $0 as? OSLogEntryLog }
            .map { Line(category: $0.category, level: $0.level, text: $0.composedMessage) }
    }

    /// A scene that logs for real, whose next save fails at `fault` with `word` in the failure.
    static func scene(_ fault: Fault, word: String) throws -> AdversarialScene {
        var setup = try fault == .generator ? AdversarialScene.Setup.unseeded : .seeded()
        setup.logger = LedgerLogger(category: category)
        let scene = AdversarialScene(setup)
        switch fault {
        case .settings: scene.settings.script.next(.fail(word))
        case .catalog: scene.exercises.script.next(.fail(word))
        case .write: scene.programs.script.next(.fail(word))
        case .generator: break
        }
        return scene
    }

    /// A save that fails once at each step it can, a retry that fails again, an unreadable unit at appearance,
    /// then a cancelled save and one that succeeds, which are no failures.
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
        let cancelled = try scene(.settings, word: "f08s2-never")
        let hold = Checkpoint()
        cancelled.exercises.script.next(.hold(hold, then: .honourCancellation))
        await cancelled.store.loadUnits()
        cancelled.store.send(.skipSetup)
        let task = Task { await cancelled.runSave() }
        await hold.arrivals()
        task.cancel()
        hold.open()
        await task.value
        #expect(cancelled.programs.offered.isEmpty)
    }

    /// The lines the failures above left, read once for the suite's two tests.
    static let logged = Task {
        let before = try lines().count
        try await runEveryFailure()
        return try Array(lines().dropFirst(before)).filter {
            $0.text.contains("f08s2-") || $0.text.contains("Barbell Bench Press") || $0.category == category
        }
    }

    @Test(
        "Each failed attempt logs one line at error level or above; a cancelled save logs none",
        .enabled(if: runsSlowTests)
    )
    func failures_everyStep_areLoggedOnce() async throws {
        let lines = try await Self.logged.value
        func count(_ word: String) -> Int {
            lines.count { $0.text.contains(word) }
        }
        #expect(count("f08s2-save-settings") == 1, "\(lines)")
        #expect(count("f08s2-save-catalog") == 1, "\(lines)")
        #expect(count("f08s2-save-write") == 1, "\(lines)")
        #expect(count("f08s2-retry") == 2, "one line for each failed attempt. \(lines)")
        #expect(count("f08s2-units") == 1, "the unreadable unit when the screen opens. \(lines)")
        #expect(count("Barbell Bench Press") == 1, "the exercise the generator missed. \(lines)")
        #expect(count("f08s2-never") == 1, "that scene's unit read failed; its cancelled save logs nothing. \(lines)")
        #expect(count("CancellationError") == 0, "\(lines)")
        #expect(lines.count == 8, "\(lines)")
        #expect(lines.allSatisfy { $0.level == .error || $0.level == .fault }, "\(lines)")
        #expect(lines.allSatisfy { !$0.text.localizedCaseInsensitiveContains("ledger") }, "\(lines)")
    }

    @Test(
        "The module logs under a category of its own, not under whichever one the injected logger has",
        .enabled(if: runsSlowTests)
    )
    func failures_areLoggedUnderTheModulesCategory() async throws {
        // Standards §8: "a category per module". The injected logger is the app's (`LedgerLogger(category: "app")`
        // live); `LedgerLogger.category(_:)` gives a module its own and keeps a disabled logger disabled.
        let lines = try await Self.logged.value
        #expect(!lines.isEmpty)
        let categories = Set(lines.map(\.category))
        #expect(!categories.contains(Self.category), "logged under the injected logger's category: \(categories)")
    }
}
