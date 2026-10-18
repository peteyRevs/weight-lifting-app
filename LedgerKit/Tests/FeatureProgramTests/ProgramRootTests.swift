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

    /// F11 S13, criteria 12 and 14: the root hosted in a window. Its tasks run the store and the session and
    /// hand a route to the app; it selects the week the app asks for, draws a message when there is no
    /// program to show, and announces the notice. What the builder draws is `ProgramAccessibilityTests`'.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @MainActor
    @Suite("ProgramRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct ProgramRootTests {
        /// What the app was handed, and what VoiceOver was told.
        @MainActor @Observable
        final class Handed {
            var routes: [ProgramRoute] = []
            var announcements: [String] = []
            var week: ProgramWeekRequest?
        }

        /// The root as the app holds it, with the week request a test changes.
        struct Hosted: View {
            let store: ProgramStore
            let handed: Handed

            var body: some View {
                ProgramRoot(store: store, week: handed.week) { handed.routes.append($0) } announce: {
                    handed.announcements.append($0)
                }
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

        @Test("14. The root's tasks run the store and the session: loaded, and an edit is stored, with no call")
        func root_runsTheStoreAndTheSession() async throws {
            let scene = try ProgramStoreScene()
            #expect(scene.store.state == .loading)
            try await Self.hosting(Hosted(store: scene.store, handed: Handed())) {
                await eventually { scene.store.state.isLoaded }
                scene.store.send(.edit(.setDeload(true, week: 0)))
                await scene.idle()
                #expect(try await scene.stored().weeks[0].isDeload)
            }
        }

        @Test("14. A route is handed to the app once")
        func root_handsARouteOnce() async throws {
            let scene = try ProgramStoreScene()
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) {
                await eventually { scene.store.state.isLoaded }
                let card = try #require(scene.model.days.cards.first)
                scene.store.send(card.action)
                scene.store.send(card.action)
                await eventually { handed.routes.count == 1 && scene.store.pendingRoute == nil }
                #expect(handed.routes == [.day(card.id, weekIndex: 4)])
            }
        }

        @Test("14. The week the app asks for is selected, on the first model and again for a new request")
        func root_selectsTheRequestedWeek() async throws {
            let scene = try ProgramStoreScene()
            let handed = Handed()
            handed.week = ProgramWeekRequest(number: 1, weekIndex: 2)
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) {
                await eventually { scene.store.state.isLoaded }
                #expect(try scene.model.week.title == "WEEK 3")
                scene.store.send(.selectWeek(6))
                handed.week = ProgramWeekRequest(number: 2, weekIndex: 2)
                await eventually { scene.store.selectedWeek == 2 }
            }
        }

        @Test("14. With no program, or one that cannot be read, the root draws its message")
        func root_drawsTheMessages() async throws {
            let empty = try ProgramStoreScene(hasProgram: false)
            await empty.running().cancel()
            let failed = try ProgramStoreScene { values, _ in values.programRepository = EndedPrograms() }
            await failed.running().cancel()
            let messages = [empty, failed].map { scene in
                Hosted(store: scene.store, handed: Handed()).accessibilityElements().map(\.label)
            }
            #expect(messages[0] == ["No program yet", "Your program appears here once you have set one up."])
            #expect(messages[1] == [
                "Can't show your program right now",
                "Your workouts are still on this iPhone. Open the app again to try once more."
            ])
        }

        @Test("12. The notice is announced when it appears and when it changes")
        func root_announcesTheNotice() async throws {
            var program = try Fixtures.seedProgram()
            program.weeks.removeLast(6)
            let scene = try ProgramStoreScene(program: program)
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) {
                await eventually { scene.store.state.isLoaded }
                try scene.store.send(scene.model.block.removeWeek)
                await eventually { handed.announcements.count == 1 }
                scene.store.send(.notice(.weekHasLoggedSessions(weekNumber: 2)))
                await eventually { handed.announcements.count == 2 }
                #expect(handed.announcements == [
                    "A block needs at least 2 weeks.", "Week 2 has logged sessions and can't be removed."
                ])
            }
        }
    }
#endif
