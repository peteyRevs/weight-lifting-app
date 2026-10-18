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
            /// The scene's phase as the test sets it, and the last one SwiftUI has shown the root. A window with
            /// no scene, as a package test's is, reports the background, where the root follows nothing.
            var phase = ScenePhase.active
            var shownPhase: ScenePhase?
        }

        /// The root as the app holds it, with the week request a test changes.
        struct Hosted: View {
            let store: ProgramStore
            let handed: Handed

            var body: some View {
                ProgramRoot(store: store, week: handed.week) { handed.routes.append($0) } announce: {
                    handed.announcements.append($0)
                }
                .environment(\.scenePhase, handed.phase)
                .onChange(of: handed.phase, initial: true) { _, phase in handed.shownPhase = phase }
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
            try await Self.hosting(Hosted(store: scene.store, handed: Handed())) { () async throws in
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
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { () async throws in
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
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { () async throws in
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

        /// Moves the scene to `phase` and returns once SwiftUI has shown the root that phase.
        private static func move(_ handed: Handed, to phase: ScenePhase) async {
            handed.phase = phase
            await eventually { handed.shownPhase == phase }
        }

        @Test("14. Back from the background the root follows the sources again; the save loop is not restarted")
        func root_backFromTheBackground_followsAgain() async throws {
            var counting: CountingPrograms?
            let scene = try ProgramStoreScene { values, probed in
                let wrapped = CountingPrograms(base: probed.programs)
                counting = wrapped
                values.programRepository = wrapped
            }
            let programs = try #require(counting)
            let handed = Handed()
            handed.phase = .background
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { () async throws in
                await eventually { handed.shownPhase == .background }
                #expect(scene.store.state == .loading, "in the background the root follows nothing")
                await Self.move(handed, to: .active)
                await eventually { scene.store.state.isLoaded }
                #expect(programs.observations == 1)
                await Self.move(handed, to: .inactive)
                await Self.move(handed, to: .background)
                await Self.move(handed, to: .active)
                // A run reads the logged weeks as it starts: the store's write of them wakes the check.
                await eventually {
                    _ = scene.store.loggedWeeks
                    return programs.observations == 2
                }
                // The save loop's task kept running through it: an edit is stored with no new run of it.
                scene.store.send(.edit(.setDeload(true, week: 0)))
                await scene.idle()
                #expect(try await scene.stored().weeks[0].isDeload)
                #expect(programs.observations == 2, "inactive alone restarts nothing")
            }
        }

        @Test("12. The notice is announced when it appears and when it changes")
        func root_announcesTheNotice() async throws {
            var program = try Fixtures.seedProgram()
            program.weeks.removeLast(6)
            let scene = try ProgramStoreScene(program: program)
            let handed = Handed()
            try await Self.hosting(Hosted(store: scene.store, handed: handed)) { () async throws in
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
