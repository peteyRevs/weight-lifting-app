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

    /// F13 S2, criteria 3 and 5, N9, through the root hosted in a window: its task runs the store, a row's route is
    /// handed to the app once, a confirmed delete runs from the root's own task and closes the detail once, and the
    /// screen is one scroll view. What the page draws is `WorkoutDetailAccessibilityTests`'. (`SceneLessWindow` is
    /// internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @MainActor
    @Suite("WorkoutDetailRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct WorkoutDetailRootTests {
        /// What the app was handed.
        @MainActor @Observable
        final class Handed {
            var routes: [HistoryRoute] = []
        }

        /// The root as the app holds it, told the scene is active (a window with no scene reports the background,
        /// where the root follows nothing).
        struct Hosted: View {
            let store: WorkoutDetailStore
            let handed: Handed

            var body: some View {
                WorkoutDetailRoot(store: store) { handed.routes.append($0) }
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

        static let newest = HistoryFixtures.twelve()[11]

        @Test("3. The root's task runs the store; a row's route is handed to the app once; one scroll view")
        func root_runsTheStore_andHandsARouteOnce() async throws {
            let scene = DetailScene(Self.newest.id)
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { view in
                await eventually { (try? scene.model) != nil }
                let route = try #require(scene.model.rowRoutes.first)
                scene.store.send(route)
                scene.store.send(route)
                await eventually { handed.routes.count == 1 && scene.store.pendingRoute == nil }
                #expect(handed.routes == [route])
                view.layoutIfNeeded()
                #expect(Self.scrollViews(in: view).count == 1)
            }
        }

        @Test("5. A confirmed delete runs from the root's task, once, and the detail is closed once")
        func root_deletesOnce_andCloses() async throws {
            let scene = DetailScene(Self.newest.id)
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { _ in
                await eventually { (try? scene.model) != nil }
                scene.store.confirmDelete()
                scene.store.confirmDelete()
                await eventually { handed.routes == [.closeWorkout(Self.newest.id)] && scene.store.pendingRoute == nil }
                #expect(scene.workouts.deleteCount == 1)
                #expect(scene.store.state == .gone)
            }
        }

        @Test("N9. A delete that fails raises its alert and keeps the detail")
        func root_failedDelete_keepsTheDetail() async throws {
            let scene = DetailScene(Self.newest.id, failsDeletes: true)
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { _ in
                await eventually { (try? scene.model) != nil }
                scene.store.confirmDelete()
                await eventually { scene.store.showsDeleteFailure }
                #expect((try? scene.model) != nil)
                #expect(handed.routes.isEmpty)
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
