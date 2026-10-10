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

        /// Hosts `view` in a window of the phone's size for as long as `body` runs, in an active scene unless
        /// `view` sets a phase of its own: a window with no scene, as a package test's is, reports the
        /// background, where the root runs nothing.
        private static func hosting(_ view: some View, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view.environment(\.scenePhase, .active))
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

        /// The scene's phase as a test sets it, and the last one SwiftUI has shown the root.
        @MainActor @Observable
        final class Phase {
            var asked = ScenePhase.active
            var shown: ScenePhase?
        }

        /// The root under a scene phase the test moves.
        struct InAScene: View {
            let phase: Phase
            let store: TodayStore

            var body: some View {
                TodayRoot(store: store) { _ in }
                    .environment(\.scenePhase, phase.asked)
                    .onChange(of: phase.asked, initial: true) { _, asked in phase.shown = asked }
            }
        }

        /// Moves the scene to `asked` and returns once SwiftUI has shown the root that phase.
        private static func move(_ phase: Phase, to asked: ScenePhase) async {
            phase.asked = asked
            await eventually { phase.shown == asked }
        }

        @Test("14. Back from the background the root runs the store again, once; no other change of phase does")
        func root_backFromTheBackground_runsTheStoreAgain() async throws {
            let scene = try TodayScene()
            let phase = Phase()
            await Self.hosting(InAScene(phase: phase, store: scene.store)) {
                await eventually { scene.store.model != nil }
                #expect(scene.store.model?.header.title == "Lower A")
                #expect(scene.workouts.ranges.count == 1)
                #expect(scene.workouts.observations == 1)

                // Control Centre over the app and away again: inactive, then active. Then a night in the
                // background, on the way there through inactive, as the system goes.
                await Self.move(phase, to: .inactive)
                await Self.move(phase, to: .active)
                await Self.move(phase, to: .inactive)
                await Self.move(phase, to: .background)
                scene.clock.value = Fixtures.date(2026, 9, 17, hour: 5, minute: 20)
                await Self.move(phase, to: .inactive)
                await Self.move(phase, to: .active)

                await eventually { scene.store.model?.header.title == "Rest day" }
                #expect(scene.store.model?.header.date == "Thursday, September 17")
                #expect(scene.workouts.ranges.count == 2)
                #expect(scene.workouts.observations == 2, "one new run for the whole trip, and none on the way out")
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
