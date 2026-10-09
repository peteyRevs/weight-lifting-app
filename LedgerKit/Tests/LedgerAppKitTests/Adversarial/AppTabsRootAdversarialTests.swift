#if os(iOS)
    import Dependencies
    import Foundation
    @testable import LedgerAppKit
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S5 adversarial round 1 (G2), the audit of the sanctioned edits to `AppTabsAdversarialTests`. With
    /// Today's root read there as "no header", its walk no longer tells Today's root from an empty screen. This
    /// walk does, by the one thing the shell can see of Today's root from outside: it is the only screen of the
    /// shell that scrolls. Exactly when Today is selected and its stack is empty the shell shows one page scroll
    /// view; on a placeholder tab, or under a pushed Settings, it shows none.
    @MainActor
    @Suite("Adversarial F09 S5 · Today's root in the tab shell, hosted")
    struct AppTabsRootAdversarialTests {
        /// Hosts the shell over `router` on empty stores, with UIKit's animations off, and hands `body` a
        /// count of the page scroll views on screen, taken after a layout pass.
        static func hosting(_ router: AppRouter, _ body: (_ count: () -> Int) -> Void) {
            let animated = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(animated) }
            withTestDependencies {
                $0.inMemoryStores()
                $0.workoutSession = FakeWorkoutSessionClient()
            } operation: {
                let host = UIHostingController(rootView: AppTabs(router: router))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                body {
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date())
                    return Self.visiblePageScrollViews(in: host.view)
                }
            }
        }

        /// SwiftUI's page scroll views under `view` that are in the window and not hidden, themselves or by
        /// a parent: a tab that is not selected and a root under a pushed screen may keep their views.
        static func visiblePageScrollViews(in view: UIView) -> Int {
            guard !view.isHidden, view.alpha > 0, view.window != nil else {
                return 0
            }
            let own = view is UIScrollView && String(describing: type(of: view)).contains("HostingScrollView")
            return (own ? 1 : 0) + view.subviews.map(visiblePageScrollViews(in:)).reduce(0, +)
        }

        @Test(
            "Random selections, opens and pops: Today's scrolling root is on screen exactly when it should be",
            arguments: 1 ... 10
        )
        func randomSequences_showTodaysRootExactlyWhenSelectedAndUnpushed(seed: Int) {
            var random = AdversarialRandom(seed: seed)
            let router = AppRouter()
            var selected = AppTab.today
            var depths: [AppTab: Int] = [:]
            Self.hosting(router) { count in
                #expect(count() == 1, "at launch")
                for step in 0 ..< 20 {
                    let tab = AppTab.allCases[Int.random(in: 0 ..< 4, using: &random)]
                    switch Int.random(in: 0 ..< 3, using: &random) {
                    case 0:
                        router.selectedTab = tab
                        selected = tab
                    case 1:
                        router.open(.settings, in: tab)
                        selected = tab
                        depths[tab, default: 0] += 1
                    default:
                        router[path: tab] = []
                        depths[tab] = 0
                    }
                    let expected = selected == .today && depths[.today, default: 0] == 0 ? 1 : 0
                    #expect(count() == expected, "seed \(seed) step \(step): \(selected), \(depths)")
                }
            }
        }
    }
#endif
