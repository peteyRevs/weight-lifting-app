@testable import FeatureOnboarding
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import OSLog
import Testing

/// F08 S2, criterion 7: "the failure is logged". The store logs through the injected logger, so the test gives
/// each scene a logger with a category of its own and reads this process's log back, once: a read costs about a
/// second, which is why the three scenes share one test.
@Suite("OnboardingStore: logging", .timeLimit(.minutes(1)))
struct OnboardingStoreLoggingTests {
    /// What this process has logged under the app's subsystem, oldest first, by category.
    private static func logged() throws -> [String: [OSLogEntryLog]] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let ours = NSPredicate(format: "subsystem == %@", LedgerLogger.subsystem)
        let entries = try store.getEntries(at: store.position(timeIntervalSinceLatestBoot: 0), matching: ours)
        return Dictionary(grouping: entries.compactMap { $0 as? OSLogEntryLog }, by: \.category)
    }

    @Test("A failure is logged once, as an error naming what failed; a success and a cancellation log nothing")
    func failures_areLoggedOnce_andNothingElseIs() async throws {
        let failedSave = "FeatureOnboardingTests.failedSave"
        try await StoreScene.run(seed: .empty, changes: [.logger(LedgerLogger(category: failedSave))]) { scene in
            await scene.startTraining()
            #expect(scene.store.state.phase == .failed)
            #expect(scene.store.model.error == "Couldn't save your program. Try again.", "all the lifter sees")
        }

        let quietSave = "FeatureOnboardingTests.quietSave"
        let gate = Gate()
        let quiet: [SceneChange] = [.logger(LedgerLogger(category: quietSave)), .catalogWaits(gate)]
        try await StoreScene.run(changes: quiet) { scene in
            scene.store.send(.skipSetup)
            let running = Task { await scene.save() }
            await gate.entered()
            running.cancel()
            await running.value
            #expect(scene.store.state.phase == .editing)
            scene.store.send(.skipSetup)
            await scene.save()
            #expect(scene.store.state.phase == .saved)
        }

        let unreadSettings = "FeatureOnboardingTests.unreadSettings"
        let unread: [SceneChange] = [.logger(LedgerLogger(category: unreadSettings)), .settingsCannotBeRead]
        try await StoreScene.run(changes: unread) { scene in
            await scene.store.loadUnits()
            #expect(scene.store.model.error == nil)
        }

        let logged = try Self.logged()
        #expect(logged[failedSave]?.map(\.level) == [.error])
        let message = try #require(logged[failedSave]?.first?.composedMessage)
        #expect(message.contains("unknownExercise") && message.contains("Barbell Bench Press"), "\(message)")
        #expect(logged[quietSave] == nil)
        #expect(logged[unreadSettings]?.map(\.level) == [.error])
    }
}
