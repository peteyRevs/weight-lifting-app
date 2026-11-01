import FeatureSettings
import Foundation
@testable import LedgerAppKit
import Testing

/// F14 S1, N7 and N6: where Settings' routes go (`Routes+Settings.swift`), and the About line's values, which the
/// app reads from its bundle (`AppAbout.swift`).
@MainActor
@Suite("Settings routes")
struct SettingsRouteMappingTests {
    @Test("N7. Diagnostics raises the Debug menu, once a route, and moves no tab and no stack")
    func debugMenu_raisesTheSheet() {
        let router = AppRouter()
        router.open(.settings, in: .today)
        var raised = 0
        router.resolve(SettingsRoute.debugMenu) { raised += 1 }
        #expect(raised == 1)
        #expect(router.selectedTab == .today)
        #expect(router[path: .today] == [.settings])
    }

    @Test("N6. The About line's values are the bundle's own keys, the display name before the name")
    func about_readsTheBundlesKeys() throws {
        let bundle = Bundle.main
        let about = AppAbout(bundle: bundle)
        let info = try #require(bundle.infoDictionary)
        #expect(about.name == (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String)
        #expect(about.version == info["CFBundleShortVersionString"] as? String)
        #expect(about.build == info["CFBundleVersion"] as? String)
        #expect(AppAbout.main == about)
    }
}
