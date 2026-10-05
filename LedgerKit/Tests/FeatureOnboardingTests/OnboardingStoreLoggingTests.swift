@testable import FeatureOnboarding
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import OSLog
import Testing

/// F08 S2, criterion 7: "the failure is logged under the module's own log category", and "a cancelled task is
/// not a failure and is not logged as one". The store logs through the injected logger, so each scene gets a
/// logger of its own and the test reads this process's log back, once.
///
/// **Nightly lane only** (testing-strategy §6). Reading the log back costs 3 to 10 seconds, and nothing cheaper
/// can see a line: `LedgerLogger` hands out an `os.Logger`, whose message is built by the compiler for the
/// system log alone, so no recording logger can be injected without changing how every module logs. The PR lane
/// therefore proves that a failure is shown and saves nothing, and not that it is logged. The read runs off the
/// main actor, so that no other test of the target waits behind it.
@Suite("OnboardingStore: logging", .tags(.feature, .slow), .timeLimit(.minutes(1)))
struct OnboardingStoreLoggingTests {
    /// One line of this process's log.
    nonisolated struct Line: Sendable, CustomStringConvertible {
        let category: String
        let isError: Bool
        let text: String

        var description: String {
            "[\(category)\(isError ? ", error" : "")] \(text)"
        }
    }

    /// What this process has logged under the app's subsystem, oldest first.
    @concurrent
    nonisolated static func logged() async throws -> [Line] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let ours = NSPredicate(format: "subsystem == %@", LedgerLogger.subsystem)
        return try store.getEntries(at: store.position(timeIntervalSinceLatestBoot: 0), matching: ours)
            .compactMap { $0 as? OSLogEntryLog }
            .map { Line(category: $0.category, isError: $0.level == .error, text: $0.composedMessage) }
    }

    /// The category of the logger the scenes inject: no line may be filed under it.
    nonisolated static let injected = "FeatureOnboardingTests.injected"

    /// A scene whose logger writes for real, and whose failing double throws `word`, by which the test finds the
    /// scene's line among whatever else the process logs under the module's category.
    private static func scene(
        failing word: String,
        _ changes: [SceneChange],
        _ body: (StoreScene) async throws -> Void
    ) async throws {
        let logging: [SceneChange] = [.logger(LedgerLogger(category: injected)), .failureWord(word)]
        try await StoreScene.run(changes: changes + logging, body: body)
    }

    /// Three failures and two cancellations, each in a scene of its own.
    ///
    /// One failure is not planted here: a store that throws `CancellationError` on a task nobody cancelled
    /// (F8-S2-7). Its line can carry no word of this suite's, and the tester's suite, which runs in this
    /// process at the same time, counts every line that says "CancellationError". That line is read by
    /// `OnboardingLoggingAdversarialTests.shownFailure_ofAnUncancelledTask_isLogged` alone.
    private static func runEveryScene() async throws {
        // 1. A save whose write fails: one line.
        try await scene(failing: "s2impl-write", [.programCannotBeSaved]) { scene in
            await scene.startTraining()
            #expect(scene.store.model.error == "Couldn't save your program. Try again.", "all the lifter sees")
        }
        // 2. A save cancelled before its write, then the same tap again, which saves: no line.
        let waiting = Gate()
        try await scene(failing: "s2impl-none", [.catalogWaits(waiting)]) { scene in
            scene.store.send(.skipSetup)
            let running = Task { await scene.save() }
            await waiting.entered()
            running.cancel()
            await running.value
            scene.store.send(.skipSetup)
            await scene.save()
            #expect(scene.store.state.phase == .saved)
        }
        // 3. The unit cannot be read when the screen appears: one line.
        try await scene(failing: "s2impl-units", [.settingsCannotBeRead]) { scene in
            await scene.store.loadUnits()
        }
        // 4. The unit read is cancelled with its task: no line.
        let reading = Gate()
        try await scene(failing: "s2impl-none", [.settingsWaitsThenThrowsCancellation(reading)]) { scene in
            let running = Task { await scene.store.loadUnits() }
            await reading.entered()
            running.cancel()
            await running.value
        }
        // 5. A real failure that arrives on a cancelled task: one line, though nothing is shown.
        let failing = Gate()
        try await scene(failing: "s2impl-cancelled-task", [.catalogWaitsThenFails(failing)]) { scene in
            scene.store.send(.skipSetup)
            let running = Task { await scene.save() }
            await failing.entered()
            running.cancel()
            await running.value
            #expect(scene.store.model.error == nil)
        }
    }

    @Test(
        "A failure is logged once, as an error, under the module's category; a cancellation logs nothing",
        .enabled(if: TestLane.runsSlowTests)
    )
    func failures_areLoggedOnce_underTheModulesCategory() async throws {
        try await Self.runEveryScene()
        let all = try await Self.logged()
        let lines = all.filter { $0.text.contains("s2impl-") }
        #expect(lines.count { $0.text.contains("s2impl-write") && $0.text.contains("could not save") } == 1)
        #expect(lines.count { $0.text.contains("s2impl-units") && $0.text.contains("could not read") } == 1)
        #expect(lines.count { $0.text.contains("s2impl-cancelled-task") } == 1, "\(lines)")
        #expect(lines.count == 3, "\(lines)")
        let areErrors = lines.allSatisfy(\.isError)
        #expect(areErrors, "\(lines)")
        #expect(lines.allSatisfy { $0.category == "onboarding" }, "the module's own category. \(lines)")
        #expect(lines.allSatisfy { !$0.text.contains("CancellationError") }, "\(lines)")
        let underTheInjected = all.filter { $0.category == Self.injected }
        #expect(underTheInjected.isEmpty, "filed under the injected logger's own category: \(underTheInjected)")
    }
}
