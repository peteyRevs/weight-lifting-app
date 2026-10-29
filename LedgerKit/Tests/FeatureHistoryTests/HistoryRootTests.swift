#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S1, criterion 6 and N2, through the root hosted in a window: its task runs the store, a row's route is
    /// handed to the app once, the failed state draws its message, and the screen is one scroll view. What the page
    /// draws is `HistoryAccessibilityTests`'. (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the
    /// `@testable` import.)
    @MainActor
    @Suite("HistoryRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct HistoryRootTests {
        /// What the app was handed.
        @MainActor @Observable
        final class Handed {
            var routes: [HistoryRoute] = []
        }

        /// The root as the app holds it, told the scene is active (a window with no scene reports the background,
        /// where the root follows nothing).
        struct Hosted: View {
            let store: HistoryStore
            let handed: Handed

            var body: some View {
                HistoryRoot(store: store) { handed.routes.append($0) }
                    .environment(\.scenePhase, .active)
            }
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

        @Test("6. The root's task runs the store; a row's route is handed to the app once")
        func root_runsTheStore_andHandsARouteOnce() async throws {
            let scene = HistoryScene(workouts: HistoryFixtures.twelve())
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { _ in
                await eventually { (try? scene.model) != nil }
                let row = try #require(scene.model.rows.first)
                scene.store.send(row.route)
                scene.store.send(row.route)
                await eventually { handed.routes.count == 1 && scene.store.pendingRoute == nil }
                #expect(handed.routes == [.workout(row.id)])
            }
        }

        @Test("The root draws one scroll view around the page")
        func root_drawsOneScrollView() async throws {
            let scene = HistoryScene(workouts: HistoryFixtures.twelve())
            try await Self.hosting(Hosted(store: scene.store, handed: Handed())) { view in
                await eventually { (try? scene.model) != nil }
                view.layoutIfNeeded()
                #expect(Self.scrollViews(in: view).count == 1)
            }
        }

        @Test("A source that ends draws the failed message")
        func root_drawsTheFailedMessage() async throws {
            let scene = HistoryScene { $0.settingsRepository = EndedSettings() }
            try await Self.hosting(Hosted(store: scene.store, handed: Handed())) { _ in
                await eventually { scene.store.state == .failed }
            }
            let failed = HistoryScene()
            failed.store.fail()
            let stops = HistoryRoot(store: failed.store) { _ in }.accessibilityElements()
            #expect(stops.map(\.label) == ["Can't show your history right now", HistoryCopy.failedBody])
            #expect(stops.first?.traits.contains(.header) == true)
        }

        /// The scroll views under `view` that scroll a page.
        private static func scrollViews(in view: UIView) -> [UIScrollView] {
            let own = (view as? UIScrollView)
                .map { String(describing: type(of: $0)).contains("HostingScrollView") ? [$0] : [] }
            return (own ?? []) + view.subviews.flatMap(scrollViews(in:))
        }
    }
#endif
