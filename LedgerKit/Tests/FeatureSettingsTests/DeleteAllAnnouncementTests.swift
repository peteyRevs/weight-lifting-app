#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import Foundation
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F14 S3, G3 SF1: a failed "Delete all data" is announced to VoiceOver when its line appears under the field, away
    /// from the focus on the button, as a failed save is (F14-S1b-2), through the root's injected `announce`.
    @MainActor
    @Suite("Delete all data · announced failure", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct DeleteAllAnnouncementTests {
        @Test("A failed erase's line is announced once when it appears; the erase that then succeeds announces nothing")
        func failedErase_isAnnounced() async throws {
            let heard = HeardAnnouncements()
            let (scene, reset) = try DeleteAllScene.erasingTheScenesStores(failures: 1)
            let root = SettingsRoot(store: scene.store) { _ in } announce: { heard.announcements.append($0) }
            try await SettingsRootAdversarialTests.hosting(root) { _ in
                await eventually { scene.store.model != nil }
                scene.store.send(.deleteAll)
                scene.store.send(.continueDeleteAll)
                scene.store.send(.setDeleteText("DELETE"))
                #expect(heard.announcements.isEmpty, "opening the sheet announces nothing")
                scene.store.send(.confirmDeleteAll)
                await eventually { !heard.announcements.isEmpty }
                #expect(heard.announcements == ["Nothing was deleted. Try again."])
                scene.store.send(.confirmDeleteAll)
                await eventually { scene.store.deleteAll == nil }
                #expect(reset.calls.count == 2)
                #expect(heard.announcements == ["Nothing was deleted. Try again."], "the erase that succeeds")
            }
        }
    }
#endif
