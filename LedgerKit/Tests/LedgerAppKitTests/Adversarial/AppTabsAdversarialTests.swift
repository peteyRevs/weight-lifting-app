#if os(iOS)
    import Foundation
    @testable import LedgerAppKit
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S1 adversarial round 1, criteria 1 to 3 on the shell itself: `AppTabs` hosted in a window over a router
    /// the test drives, read as VoiceOver reads it. What is on screen must be the top of the selected tab's stack,
    /// through selections, opens in this and other tabs, pops and returns, checked against a model over seeded
    /// random sequences. The tab bar is the system's and is not in a hosted view's tree; the running app's is read
    /// by `Apps/LedgerUITests/TabsAdversarial.swift`.
    @Suite("Adversarial F09 S1 · the tab shell, hosted")
    struct AppTabsAdversarialTests {
        static let roots: [(tab: AppTab, title: String)] = [
            (.today, "Today"), (.program, "Program"), (.library, "Library"), (.history, "History")
        ]

        /// The labels of the headers VoiceOver finds, top to bottom: one per screen that is on screen.
        static func headers(_ elements: [NSObject]) -> [String] {
            elements.filter { $0.accessibilityTraits.contains(.header) }.map { $0.accessibilityLabel ?? "" }
        }

        /// Hosts the shell over `router` with UIKit's animations off, so a push or a pop is done when it returns.
        static func hosting<Result>(_ router: AppRouter, _ body: (_ read: () -> [NSObject]) -> Result) -> Result {
            let animated = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(animated) }
            return AppTabs(router: router).withLiveAccessibilityElements(SnapshotAppearance(.light, .large), body)
        }

        @Test("At launch the shell shows Today's placeholder and nothing else: one element, the title, a header")
        func launch_showsTodaysPlaceholderAlone() {
            Self.hosting(AppRouter()) { read in
                let elements = read()
                #expect(elements.map(\.accessibilityLabel) == ["Today"])
                #expect(Self.headers(elements) == ["Today"])
            }
        }

        @Test("Each tab's root is the placeholder that names it, a header, whichever way the lifter goes round")
        func eachTab_showsThePlaceholderThatNamesIt() {
            let router = AppRouter()
            Self.hosting(router) { read in
                for root in Self.roots + Self.roots.reversed() {
                    router.selectedTab = root.tab
                    let elements = read()
                    #expect(elements.map(\.accessibilityLabel) == [root.title], "\(root.tab)")
                    #expect(Self.headers(elements) == [root.title], "\(root.tab)")
                }
            }
        }

        @Test("A destination opened in a tab never visited is shown there under a bar; both tabs keep their stacks")
        func open_inAnotherTab_showsItThere_andKeepsBothStacks() {
            let router = AppRouter()
            Self.hosting(router) { read in
                let rootTop = read().first?.accessibilityFrame.minY ?? 0
                router.open(.settings, in: .history)
                #expect(Self.headers(read()) == ["Settings"])
                #expect((read().first?.accessibilityFrame.minY ?? 0) > rootTop, "a pushed screen keeps its bar")
                router.selectedTab = .today
                #expect(Self.headers(read()) == ["Today"], "Today is where the lifter left it")
                router.selectedTab = .history
                #expect(Self.headers(read()) == ["Settings"], "and so is History: its stack survived")
                router.open(.settings, in: .history)
                #expect(Self.headers(read()) == ["Settings"])
                router[path: .history].removeLast()
                #expect(Self.headers(read()) == ["Settings"], "one pop of two pushes")
                router[path: .history] = []
                #expect(Self.headers(read()) == ["History"])
                #expect((read().first?.accessibilityFrame.minY ?? 0) == rootTop, "the root hides the bar again")
            }
        }

        @Test(
            "Random selections, opens, pops and returns: the shell shows the top of the selected tab's stack",
            arguments: 1 ... 40
        )
        func randomSequences_showTheTopOfTheSelectedStack(seed: Int) {
            var random = AdversarialRandom(seed: seed)
            let router = AppRouter()
            var selected = AppTab.today
            var depths: [AppTab: Int] = [:]
            Self.hosting(router) { read in
                for step in 0 ..< 25 {
                    let root = Self.roots[Int.random(in: 0 ..< 4, using: &random)]
                    switch Int.random(in: 0 ..< 4, using: &random) {
                    case 0:
                        router.selectedTab = root.tab
                        selected = root.tab
                    case 1:
                        router.open(.settings, in: root.tab)
                        selected = root.tab
                        depths[root.tab, default: 0] += 1
                    case 2 where depths[selected, default: 0] > 0:
                        router[path: selected].removeLast()
                        depths[selected, default: 0] -= 1
                    default:
                        router[path: root.tab] = []
                        depths[root.tab] = 0
                    }
                    let title = Self.roots.first { $0.tab == selected }?.title ?? ""
                    let expected = depths[selected, default: 0] > 0 ? "Settings" : title
                    #expect(Self.headers(read()) == [expected], "seed \(seed) step \(step)")
                }
            }
        }

        @Test(
            "At the largest text size a placeholder's title is whole and on one line, down to an iPhone SE zoomed",
            arguments: ["Today", "Program", "Library", "History", "Settings"], [CGFloat(375), 320]
        )
        func largestTextSize_titleIsWholeOnOneLine(title: String, width: CGFloat) throws {
            let largest = SnapshotAppearance(.light, .accessibility5)
            func frame(_ text: String, width: CGFloat) throws -> CGRect {
                let screen = PlaceholderScreen(text, identifier: "x.title").frame(width: width, height: 568)
                return try #require(screen.accessibilityElements(largest).first).frame
            }
            let narrow = try frame(title, width: width)
            let wide = try frame(title, width: SnapshotConfig.phoneWidth)
            let oneLetter = try frame("T", width: width)
            #expect(narrow.width == wide.width, "the title is cut or wrapped at \(width) pt")
            #expect(narrow.height == oneLetter.height, "the title takes more than one line at \(width) pt")
        }
    }
#endif
