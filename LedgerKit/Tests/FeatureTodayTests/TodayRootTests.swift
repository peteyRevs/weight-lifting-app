#if os(iOS) && DEBUG
    @testable import FeatureToday
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S5, criterion 8: the root hosted in a window. Its tasks run the store and hand a route to the app;
    /// what the screen draws from a state is `TodayAccessibilityTests`' and the references'.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @MainActor
    @Suite("TodayRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct TodayRootTests {
        /// What the app was handed.
        @MainActor
        final class Handed {
            var routes: [TodayRoute] = []
            var longPresses = 0
        }

        /// Hosts `view` in a window of the phone's size for as long as `body` runs.
        private static func hosting(_ view: some View, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: TodayScreenTests.phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        @Test("The root's task runs the store: the day is loaded with no call from outside")
        func root_runsTheStore() async throws {
            let scene = try TodayScene()
            #expect(scene.store.phase == "idle")
            await Self.hosting(TodayRoot(store: scene.store) { _ in }) {
                await eventually { scene.store.model != nil }
                #expect(scene.store.model?.card.upNext?.title == "Lower A — Squat focus")
            }
        }

        @Test("A route the screen asks for reaches the app once, and the store forgets it")
        func root_handsARouteOnOnce() async throws {
            let scene = try TodayScene()
            let handed = Handed()
            let root = TodayRoot(store: scene.store) { handed.routes.append($0) }
            await Self.hosting(root) {
                await eventually { scene.store.model != nil }
                scene.store.send(.settings)
                scene.store.send(.settings)
                await eventually { scene.store.pendingRoute == nil }
                #expect(handed.routes == [.settings])

                scene.store.send(.resumeWorkout)
                await eventually { scene.store.pendingRoute == nil }
                #expect(handed.routes == [.settings, .resumeWorkout])
            }
        }
    }
#endif
