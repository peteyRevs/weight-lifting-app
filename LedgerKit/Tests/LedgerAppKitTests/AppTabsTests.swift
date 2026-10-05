#if os(iOS)
    @testable import LedgerAppKit
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S1 criteria 1–3 in SwiftUI itself: the shell hosted in a window on the simulator, driven through its
    /// router, read as VoiceOver reads it. What a tab shows is one element here, its title as a heading (the
    /// pinned tree of the shell's content). The tab bar's own buttons are not in a hosted view's tree; the `Tabs`
    /// UI test pins them in the running app.
    @MainActor
    @Suite("AppTabs")
    struct AppTabsTests {
        /// A screen's title: a heading, read as text.
        private static let heading: UIAccessibilityTraits = [.header, .staticText]

        @Test("Each tab shows its own screen, titled as the tab", arguments: [
            (AppTab.today, "Today"), (.program, "Program"), (.library, "Library"), (.history, "History")
        ])
        func selectedTab_showsItsOwnScreen(tab: AppTab, title: String) {
            let router = AppRouter()
            router.selectedTab = tab
            let elements = AppTabs(router: router).accessibilityElements()
            #expect(elements.map(\.label) == [title])
            #expect(elements.map(\.traits) == [Self.heading])
            #expect(elements.map(\.value) == [""])
        }

        @Test("Selecting a tab through the router swaps the screen, and back")
        func selectingATab_swapsTheScreen() {
            let router = AppRouter()
            AppTabs(router: router).withLiveAccessibilityElements { read in
                #expect(Self.labels(read()) == ["Today"])
                router.selectedTab = .history
                #expect(Self.labels(read()) == ["History"])
                router.selectedTab = .today
                #expect(Self.labels(read()) == ["Today"])
            }
        }

        @Test("An opened destination is shown in its tab, and the tab keeps it while another tab is selected")
        func openedDestination_staysOnItsTabsStack() {
            let router = AppRouter()
            AppTabs(router: router).withLiveAccessibilityElements { read in
                router.open(.settings, in: .library)
                #expect(Self.labels(read()) == ["Settings"])

                router.selectedTab = .today
                #expect(Self.labels(read()) == ["Today"])
                #expect(router[path: .library] == [.settings])

                router.selectedTab = .library
                #expect(Self.labels(read()) == ["Settings"])
                #expect(router[path: .library] == [.settings])
                #expect(router[path: .today].isEmpty)
            }
        }

        @Test(
            "A destination opens on any tab's stack: every stack is keyed by AppDestination",
            arguments: AppTab.allCases
        )
        func destination_opensOnEveryTab(_ tab: AppTab) {
            let router = AppRouter()
            router.open(.settings, in: tab)
            #expect(AppTabs(router: router).accessibilityElements().map(\.label) == ["Settings"])
            #expect(router[path: tab] == [.settings])
        }

        private static func labels(_ elements: [NSObject]) -> [String] {
            elements.map { $0.accessibilityLabel ?? "" }
        }
    }
#endif
