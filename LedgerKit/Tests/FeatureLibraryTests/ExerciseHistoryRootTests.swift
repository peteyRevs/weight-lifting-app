#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F12 S2, criterion 11 and N13, through the root hosted in a window, as `LibraryRootTests`: its task runs the
    /// store, a session's route is handed to the app once, and the failed state draws its message.
    @MainActor
    @Suite("ExerciseHistoryRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct ExerciseHistoryRootTests {
        struct Hosted: View {
            let store: ExerciseHistoryStore
            let handed: LibraryRootTests.Handed

            var body: some View {
                NavigationStack {
                    ExerciseHistoryRoot(store: store) { handed.routes.append($0) }
                }
                .environment(\.scenePhase, .active)
            }
        }

        @Test("The root's task runs the store; a session's route is handed to the app once")
        func root_runsTheStore_andHandsARouteOnce() async throws {
            let scene = try HistoryScene(workouts: HistoryScene.benchWorkouts())
            let handed = LibraryRootTests.Handed()
            let host = UIHostingController(rootView: Hosted(store: scene.store, handed: handed))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            await eventually { (try? scene.model) != nil }
            let entry = try #require(scene.model.log.entries.first)
            scene.store.send(entry.route)
            scene.store.send(entry.route)
            await eventually { handed.routes.count == 1 && scene.store.pendingRoute == nil }
            #expect(handed.routes == [.openWorkout(entry.id)])
        }

        @Test("An exercise that is not stored draws the failed message")
        func root_drawsTheFailedMessage() async throws {
            let scene = try HistoryScene(exercise: ExerciseID(Fixtures.uuid(999)))
            let run = await scene.running()
            run.cancel()
            #expect(scene.store.state == .failed)
            let stops = ExerciseHistoryRoot(store: scene.store) { _ in }.accessibilityElements()
            #expect(stops.map(\.label) == ["Can't show this exercise's history right now", LibraryCopy.failedBody])
            #expect(stops.first?.traits.contains(.header) == true)
        }
    }
#endif
