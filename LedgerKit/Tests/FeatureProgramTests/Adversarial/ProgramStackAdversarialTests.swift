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

    /// F11 S14 adversarial round 1: the builder at the root of a navigation stack, as the Program tab holds it
    /// (criteria 9 and 23, ruling R10). Today's "Edit this week" asks for a week once; the lifter then picks
    /// another and opens a day. Coming back from the pushed screen, or from another tab, is the same root seen
    /// again, not a new request: the week the lifter picked must still be selected.
    @MainActor
    @Suite(
        "Adversarial F11 S14 · the builder under a pushed screen",
        .serialized,
        .tags(.feature),
        .timeLimit(.minutes(1))
    )
    struct ProgramStackAdversarialTests {
        /// The stack's path and how often the builder has appeared, changed by a test while it is hosted.
        @MainActor @Observable
        final class Stack {
            var path: [Int] = []
            var week: ProgramWeekRequest?
            var builderAppearances = 0
            var pushedAppearances = 0
            var tab = 0
        }

        /// The builder at the root of a stack, with one plain screen to push over it.
        struct Pushing: View {
            let store: ProgramStore
            @Bindable var stack: Stack

            var body: some View {
                NavigationStack(path: $stack.path) {
                    ProgramRoot(store: store, week: stack.week, onRoute: { _ in }, announce: { _ in })
                        .onAppear { stack.builderAppearances += 1 }
                        .navigationDestination(for: Int.self) { _ in
                            Text(verbatim: "pushed").onAppear { stack.pushedAppearances += 1 }
                        }
                }
                .environment(\.scenePhase, .active)
            }
        }

        /// The builder's stack in one tab of two, as `AppTabs` holds it.
        struct Tabbed: View {
            let store: ProgramStore
            @Bindable var stack: Stack

            var body: some View {
                TabView(selection: $stack.tab) {
                    Tab("Today", systemImage: "sun.max", value: 0) {
                        Text(verbatim: "today")
                    }
                    Tab("Program", systemImage: "calendar", value: 1) {
                        NavigationStack {
                            ProgramRoot(store: store, week: stack.week, onRoute: { _ in }, announce: { _ in })
                                .onAppear { stack.builderAppearances += 1 }
                        }
                    }
                }
                .environment(\.scenePhase, .active)
            }
        }

        private static func hosting(_ view: some View, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        /// Lets SwiftUI finish the update that made the builder appear again.
        private static func settle() async {
            for _ in 0 ..< 20 {
                await Task.yield()
            }
        }

        @Test("R10: a week asked for once, then another picked; back from a pushed screen the picked week stays")
        func requestedWeek_thenPicked_survivesAPushAndPop() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
                await s13Until { rig.store.selectedWeek == 1 }
                rig.store.send(.selectWeek(5))
                #expect(rig.store.selectedWeek == 5)
                stack.path = [1]
                await s13Until { stack.pushedAppearances == 1 }
                stack.path = []
                await s13Until { stack.builderAppearances == 2 }
                await Self.settle()
                #expect(rig.store.selectedWeek == 5, "the lifter's week, not the old request again")
            }
        }

        @Test("R10: a week asked for once, then another picked; back from another tab the picked week stays")
        func requestedWeek_thenPicked_survivesATabSwitch() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            stack.tab = 1
            await Self.hosting(Tabbed(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                stack.week = ProgramWeekRequest(number: 1, weekIndex: 1)
                await s13Until { rig.store.selectedWeek == 1 }
                rig.store.send(.selectWeek(5))
                let before = stack.builderAppearances
                stack.tab = 0
                await Self.settle()
                stack.tab = 1
                await s13Until { stack.builderAppearances > before }
                await Self.settle()
                #expect(rig.store.selectedWeek == 5, "the lifter's week, not the old request again")
            }
        }

        @Test("R1 hosted: an edit whose write is held when the builder is covered is stored once, uncovered or not")
        func heldWrite_whenAScreenIsPushed_isStoredOnce() async throws {
            let rig = try S13Rig()
            let stack = Stack()
            try await Self.hosting(Pushing(store: rig.store, stack: stack)) {
                await s13Until { rig.model != nil }
                await rig.probe.hold(.updateProgram)
                rig.store.send(.addWeek(selecting: 8))
                try await rig.probe.waitUntilHeld()
                stack.path = [1]
                await s13Until { stack.pushedAppearances == 1 }
                await rig.probe.release()
                stack.path = []
                await s13Until { stack.builderAppearances == 2 }
                await rig.settled()
                await s13Until { rig.session.shown?.weeks.count == 9 }
                #expect(try await rig.storedProgram()?.weeks.count == 9, "one week added, once")
            }
        }
    }
#endif
