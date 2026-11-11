#if os(iOS) && DEBUG
    import Dependencies
    @testable import FeatureHistory
    import LedgerDependencies
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
            var closes: [EditSetsClosing] = []
            var announced: [String] = []
        }

        private static func hosting(_ scene: EditScene, _ told: Told, _ body: () async throws -> Void) async rethrows {
            let sheet = EditSetsSheet(store: scene.store) { told.closes.append($0) } announce: {
                told.announced.append($0)
            }
            try await hosting(sheet) { _ in try await body() }
        }

        private static func hosting(_ sheet: EditSetsSheet, _ body: (UIView) async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: sheet)
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

        @Test("N12. An accepted save runs from the sheet's task, once, and closes the sheet once")
        func save_runsFromTheTask_andCloses() async throws {
            let scene = EditScene()
            let told = Told()
            try await Self.hosting(scene, told) {
                try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
                scene.store.send(.save)
                await eventually { told.closes == [.saved(scene.store.draft)] }
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

        @Test("N12. The sheet as the app makes it says a failed save to VoiceOver, and logs it")
        func appsAnnouncement_saysAFailure() async throws {
            let scene = EditScene(saveFailure: DetailWorkouts.DeleteFailed(), logger: LedgerLogger(category: "test"))
            let told = Told()
            try await Self.hosting(EditSetsSheet(store: scene.store) { told.closes.append($0) }) { view in
                try scene.store.send(.step(scene.firstSet.id, .weight, .upward))
                scene.store.send(.save)
                await eventually { scene.store.saveFailed }
                view.layoutIfNeeded() // the update that draws the failure's line runs its announcement
                #expect(scene.store.model.foot.problem == "Couldn't save your changes. Try again in a moment.")
                #expect(told.closes.isEmpty)
            }
        }

        @Test("N15. VoiceOver's swipe down on a weight steps it down")
        func adjustableDown_stepsTheWeightDown() throws {
            let scene = EditScene()
            let set = try scene.firstSet
            EditSetsPage(model: scene.store.model, send: scene.store.send).withAccessibilityElements { elements in
                elements.first { $0.accessibilityLabel == "Set 1 weight" }?.accessibilityDecrement()
            }
            #expect(scene.store.draft.exercises[0].sets[0].weight < set.weight)
        }

        @Test("N12. The root's sheet tells the detail how it came down: Cancel closes it, and the receipt stays")
        func rootsSheet_cancelReachesTheDetail() async throws {
            let scene = DetailScene(HistoryFixtures.twelve()[11].id)
            let run = await scene.running()
            defer { run.cancel() }
            scene.store.edit()
            let request = try #require(scene.store.editing)
            let sheet = withTestDependencies {
                $0.workoutRepository = scene.workouts
            } operation: {
                WorkoutDetailRoot.editSheet(request, over: scene.store)
            }
            sheet.withAccessibilityElements(outsideScrollViews: true) { elements in
                #expect(elements.first { $0.accessibilityLabel == "Cancel" }?.accessibilityActivate() == true)
            }
            #expect(scene.store.editing == nil)
            #expect(try scene.model.edit == "Edit")
        }
    }
#endif
