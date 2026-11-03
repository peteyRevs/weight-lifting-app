#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S3, N12, through the sheet hosted in a window: its task runs an accepted save once, a save that went through
    /// closes it once, a failure keeps it up and is announced, and a workout deleted meanwhile waits for its alert.
    /// What
    /// it draws is `EditSetsAccessibilityTests`'. (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the
    /// `@testable` import.)
    @MainActor
    @Suite("EditSetsSheet", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct EditSetsSheetTests {
        /// What the detail and VoiceOver were told.
        @MainActor @Observable
        final class Told {
            var closes: [Bool] = []
            var announced: [String] = []
        }

        private static func hosting(_ scene: EditScene, _ told: Told, _ body: () async throws -> Void) async rethrows {
            let sheet = EditSetsSheet(store: scene.store) { told.closes.append($0) } announce: {
                told.announced.append($0)
            }
            let host = UIHostingController(rootView: sheet)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        @Test("N12. An accepted save runs from the sheet's task, once, and closes the sheet once")
        func save_runsFromTheTask_andCloses() async throws {
            let scene = EditScene()
            let told = Told()
            try await Self.hosting(scene, told) {
                try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
                scene.store.send(.save)
                await eventually { told.closes == [false] }
                #expect(scene.workouts.saveCount == 1)
                #expect(told.announced.isEmpty)
            }
        }

        @Test("N12. A failed save stays up, and its line is announced")
        func failedSave_staysUp_andIsAnnounced() async throws {
            let scene = EditScene(saveFailure: DetailWorkouts.DeleteFailed())
            let told = Told()
            try await Self.hosting(scene, told) {
                try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
                scene.store.send(.save)
                await eventually { !told.announced.isEmpty }
                #expect(told.announced == ["Couldn't save your changes. Try again in a moment."])
                #expect(told.closes.isEmpty)
            }
        }

        @Test("N12. A workout deleted meanwhile raises the alert, and does not close by itself")
        func workoutGone_waitsForItsAlert() async throws {
            let scene = EditScene()
            let told = Told()
            try await Self.hosting(scene, told) {
                try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
                try await scene.memory.workouts.delete(id: scene.workout.id)
                scene.store.send(.save)
                await eventually { scene.store.phase == .workoutGone }
                #expect(told.closes.isEmpty)
            }
        }
    }
#endif
