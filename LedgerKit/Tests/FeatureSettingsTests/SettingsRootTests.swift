#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F14 S1, N7, N8 and criterion 1, through the root hosted in a window: before the settings are read it draws the
    /// title alone; its task runs the store, and a change saved through it is stored;
    /// Diagnostics' route is handed to the app once; and the screen is one scroll view. What the page draws is
    /// `SettingsAccessibilityTests`'. (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the
    /// `@testable` import.)
    @MainActor
    @Suite("SettingsRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct SettingsRootTests {
        /// What the app was handed.
        @MainActor @Observable
        final class Handed {
            var routes: [SettingsRoute] = []
        }

        /// Hosts `view` in a window of the phone's size for as long as `body` runs, and hands it the hosting view.
        private static func hosting(_ view: some View, _ body: (UIView) async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body(host.view)
        }

        /// The identifier, `settings.title`, is read by the UI tests (`Today`, `Settings`): the hosted reader's
        /// elements do not hand it over.
        @Test("N8. Before the settings are read the root draws the title alone, as a heading")
        func loading_drawsTheTitle() {
            let scene = SettingsScene()
            let elements = SettingsRoot(store: scene.store) { _ in }.accessibilityElements()
            #expect(elements.map(\.label) == ["Settings"])
            #expect(elements.first?.traits.contains(.header) == true)
        }

        @Test("Criterion 1. The root's task runs the store: KG is saved and drawn; Diagnostics is handed on once")
        func root_runsTheStore_savesAndHandsARouteOnce() async throws {
            let scene = SettingsScene()
            let handed = Handed()
            try await Self.hosting(SettingsRoot(store: scene.store) { handed.routes.append($0) }) { _ in
                await eventually { scene.store.model != nil }
                scene.store.send(.setUnits(.kg))
                await eventually { scene.store.pending == nil }
                #expect(try await scene.stored().units == .kg)
                let diagnostics = try #require(scene.model.diagnostics).action
                scene.store.send(diagnostics)
                scene.store.send(diagnostics)
                await eventually { handed.routes.count == 1 && scene.store.pendingRoute == nil }
                #expect(handed.routes == [.debugMenu])
            }
        }

        @Test("The root draws one scroll view around the page")
        func root_drawsOneScrollView() async throws {
            let scene = SettingsScene()
            try await Self.hosting(SettingsRoot(store: scene.store) { _ in }) { view in
                await eventually { scene.store.model != nil }
                view.layoutIfNeeded()
                #expect(Self.scrollViews(in: view).count == 1)
            }
        }

        /// The scroll views under `view` that scroll a page.
        private static func scrollViews(in view: UIView) -> [UIScrollView] {
            let own = (view as? UIScrollView)
                .map { String(describing: type(of: $0)).contains("HostingScrollView") ? [$0] : [] }
            return (own ?? []) + view.subviews.flatMap(scrollViews(in:))
        }
    }
#endif
