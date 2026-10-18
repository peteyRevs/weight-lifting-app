#if os(iOS)
    import Dependencies
    @testable import LedgerAppKit
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S1 criteria 1–3 in SwiftUI itself: the shell hosted in a window on the simulator, driven through its
    /// router, read as VoiceOver reads it. What a placeholder tab shows is one element here, its title as a
    /// heading (the pinned tree of the shell's content). The tab bar's own buttons are not in a hosted view's
    /// tree; the `Tabs` UI test pins them in the running app.
    ///
    /// Since F11 S14 the Program tab is `FeatureProgram`'s builder, which in a window with no scene is told it is
    /// in the background and follows nothing (`ProgramRoot`): it draws the ground alone, and has no element here.
    /// What it draws is `FeatureProgramTests`'; that the running app shows it is the `Tabs` UI test's.
    ///
    /// Since F09 S5 the Today tab is `FeatureToday`'s root. It reads the stores and the session, so the shell is
    /// hosted on empty in-memory stores and a session with nothing live; and all of it scrolls, so the shell is
    /// read outside scroll views (testing-strategy §2.6: the subject is the shell, whose own parts are pinned),
    /// where the Today tab's root has no element. What Today's page says is `FeatureTodayTests`'; that the
    /// running app shows it is the `Today` UI test's.
    @MainActor
    @Suite("AppTabs")
    struct AppTabsTests {
        /// A screen's title: a heading, read as text.
        private static let heading: UIAccessibilityTraits = [.header, .staticText]

        /// Hosts the shell over `router` on test dependencies and hands `body` a reader of what is outside
        /// its scroll views.
        private static func hosting(_ router: AppRouter, _ body: (_ read: () -> [NSObject]) -> Void) {
            withTestDependencies {
                $0.inMemoryStores()
                $0.workoutSession = FakeWorkoutSessionClient()
            } operation: {
                AppTabs(router: router).withLiveAccessibilityElements(outsideScrollViews: true, body)
            }
        }

        @Test(
            "Each placeholder tab shows its own screen, titled as the tab; Today's root is all one scroll view",
            arguments: [
                (AppTab.today, String?.none), (.program, nil), (.library, "Library"), (.history, "History")
            ]
        )
        func selectedTab_showsItsOwnScreen(tab: AppTab, title: String?) {
            let router = AppRouter()
            router.selectedTab = tab
            Self.hosting(router) { read in
                let elements = read()
                #expect(Self.labels(elements) == [title].compactMap(\.self))
                #expect(elements.map(\.accessibilityTraits) == [title].compactMap { $0.map { _ in Self.heading } })
                #expect(elements.map { $0.accessibilityValue ?? "" } == [title].compactMap { $0.map { _ in "" } })
            }
        }

        @Test("Selecting a tab through the router swaps the screen, and back")
        func selectingATab_swapsTheScreen() {
            let router = AppRouter()
            Self.hosting(router) { read in
                #expect(Self.labels(read()) == [])
                router.selectedTab = .history
                #expect(Self.labels(read()) == ["History"])
                router.selectedTab = .today
                #expect(Self.labels(read()) == [])
            }
        }

        @Test("An opened destination is shown in its tab, and the tab keeps it while another tab is selected")
        func openedDestination_staysOnItsTabsStack() {
            let router = AppRouter()
            Self.hosting(router) { read in
                router.open(.settings, in: .library)
                #expect(Self.labels(read()) == ["Settings"])

                router.selectedTab = .today
                #expect(Self.labels(read()) == [])
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
            Self.hosting(router) { read in
                #expect(Self.labels(read()) == ["Settings"])
            }
            #expect(router[path: tab] == [.settings])
        }

        @Test("The Today tab draws Today's root, the one screen of the shell that scrolls; a placeholder tab does not")
        func todayTab_isTodaysScrollingRoot() {
            #expect(Self.scrollViewCount(selecting: .today) == 1)
            #expect(Self.scrollViewCount(selecting: .history) == 0)
        }

        /// How many scroll views the shell holds with `tab` selected, hosted at the phone's size.
        private static func scrollViewCount(selecting tab: AppTab) -> Int {
            let router = AppRouter()
            router.selectedTab = tab
            return withTestDependencies {
                $0.inMemoryStores()
                $0.workoutSession = FakeWorkoutSessionClient()
            } operation: {
                let host = UIHostingController(rootView: AppTabs(router: router))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                host.view.layoutIfNeeded()
                return scrollViews(in: host.view).count
            }
        }

        /// The scroll views under `view` that scroll a page: the tab bar's own are not SwiftUI's hosting ones.
        private static func scrollViews(in view: UIView) -> [UIScrollView] {
            let own = (view as? UIScrollView)
                .map { String(describing: type(of: $0)).contains("HostingScrollView") ? [$0] : [] }
            return (own ?? []) + view.subviews.flatMap(scrollViews(in:))
        }

        @Test("The tab bar's tint ends at each stack: what a tab fills with the tint is drawn as with none around it")
        func tabContentTint_setsTheTintBack() throws {
            // A shape filled with the tint is drawn by SwiftUI itself, so `ImageRenderer` shows its colour (a
            // system control is drawn by UIKit, and comes out as a placeholder whatever its tint).
            let probe = Rectangle().fill(.tint).frame(width: 40, height: 40)
            let plain = try #require(Self.centre(of: probe))
            let tinted = try #require(Self.centre(of: probe.tint(LedgerColor.accentText)))
            let reset = try #require(Self.centre(of: probe.tabContentTint().tint(LedgerColor.accentText)))
            #expect(!tinted.differs(from: Pixel(hex: 0xFF5B22), by: 2), "control: the probe wears the tint around it")
            #expect(plain.differs(from: tinted, by: 40), "control: the system's tint is another colour")
            #expect(reset == plain)
        }

        /// The middle pixel of `view`, drawn in the dark theme, where `accentText` is the accent itself.
        private static func centre(of view: some View) -> Pixel? {
            RenderedImage.render(view, width: 40, height: 40, colorScheme: .dark)
                .flatMap(PixelBuffer.init)
                .map { $0.pixel(column: 20, row: 20) }
        }

        private static func labels(_ elements: [NSObject]) -> [String] {
            elements.map { $0.accessibilityLabel ?? "" }
        }
    }
#endif
