#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S14, criterion 20: the Day editor's root hosted in a window. Its tasks run the store and the session
    /// and hand the close to the app once; with a source that ends it draws the builder's message. What the
    /// editor draws is `DayEditorAccessibilityTests`'; the sheet, the alert and the swipe back are the nightly UI
    /// tests' (`Apps/LedgerUITests/DayEditor.swift`).
    @MainActor
    @Suite("DayEditorRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct DayEditorRootTests {
        /// What the app was handed.
        @MainActor @Observable
        final class Handed {
            var routes: [ProgramRoute] = []
        }

        /// The root as the app pushes it, in a scene the test says is active.
        struct Hosted: View {
            let store: DayEditorStore
            let handed: Handed

            var body: some View {
                DayEditorRoot(store: store) { handed.routes.append($0) }
                    .environment(\.scenePhase, .active)
            }
        }

        /// Hosts `view` in a window of the phone's size for as long as `body` runs.
        private static func hosting(_ view: some View, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: ProgramScreenTests.phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        @Test("20. The root's tasks run the store and the session: the day is drawn, and an edit is stored")
        func root_runsTheStoreAndTheSession() async throws {
            let scene = try DayEditorStoreScene()
            #expect(scene.store.state == .loading)
            try await Self.hosting(Hosted(store: scene.store, handed: Handed())) { () async throws in
                await eventually { scene.store.state != .loading }
                scene.store.send(.rename("Push", day: scene.store.day))
                await scene.idle()
                #expect(try await scene.storedDay()?.name == "Push")
            }
        }

        @Test("20. \"Done\" is handed to the app once, as the close of the day")
        func root_handsTheCloseOnce() async throws {
            let scene = try DayEditorStoreScene()
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { () async throws in
                await eventually { scene.store.state != .loading }
                let done = try scene.content.header.done.action
                scene.store.send(done)
                scene.store.send(done)
                await eventually { handed.routes.count == 1 && scene.store.pendingRoute == nil }
                #expect(handed.routes == [.closeDay])
            }
        }

        @Test("20. With a source that ends, the root draws \"Program\" over the builder's message, and it goes back")
        func root_drawsTheFailedMessage() async throws {
            let scene = try DayEditorStoreScene { values, _ in values.programRepository = EndedPrograms() }
            await scene.running().cancel()
            #expect(scene.store.state == .failed)
            let handed = Handed()
            let labels = Hosted(store: scene.store, handed: handed).accessibilityElements().map(\.label)
            #expect(labels == [
                "Program",
                "Can't show your program right now",
                "Your workouts are still on this iPhone. Open the app again to try once more."
            ])
            // Review S14 SF-1: its tap is the editor's "Program", which closes it.
            scene.store.send(.route(.closeDay))
            #expect(scene.store.pendingRoute?.route == .closeDay)
        }
    }
#endif
