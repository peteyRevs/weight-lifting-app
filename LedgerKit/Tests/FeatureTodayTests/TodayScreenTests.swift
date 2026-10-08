#if os(iOS)
    @testable import FeatureToday
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S4, criterion 2: what exists only because Today scrolls. The screen, hosted at an iPhone 17's size,
    /// is one scroll view around its page and nothing pinned; the sheet is one scroll view under its title.
    /// What the page says is `TodayAccessibilityTests`'; the stops inside the real scroll view are S5's nightly
    /// UI test. (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @Suite("Today screen", .serialized, .tags(.feature))
    struct TodayScreenTests {
        /// An iPhone 17's screen, the phone the references are drawn for.
        nonisolated static let phone = CGSize(width: SnapshotConfig.phoneWidth, height: 874)

        /// The scroll views under `view`, hosted in a window of the phone's size at `textSize`.
        private static func scrollViews(in view: some View, at textSize: DynamicTypeSize) -> [UIScrollView] {
            let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, textSize))
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            return found(in: host.view)
        }

        private static func found(in view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(found(in:))
        }

        @Test("In every state the screen is one scroll view, as wide as the phone", arguments: TodayPreview.allCases)
        func screen_isOneScrollView(_ preview: TodayPreview) {
            let screen = TodayScreen(state: preview.state) { _ in }
            let scrolls = Self.scrollViews(in: screen, at: .large)
            #expect(scrolls.count == 1)
            #expect(scrolls.first?.bounds.width == Self.phone.width)
        }

        @Test("At the largest text size of the matrix a loaded page is longer than the screen, and scrolls")
        func loadedPage_atAnAccessibilitySize_scrolls() throws {
            let screen = TodayScreen(state: TodayPreview.upNext.state) { _ in }
            let scroll = try #require(Self.scrollViews(in: screen, at: .accessibility3).first)
            #expect(scroll.contentSize.height > Self.phone.height + 100)
            #expect(scroll.contentSize.width <= Self.phone.width, "it never scrolls sideways")
        }

        @Test("The off-schedule sheet is its title over one scroll view")
        func sheet_isOneScrollView() {
            let sheet = TodayPreview.offSchedule.content
            #expect(Self.scrollViews(in: sheet, at: .large).count == 1)
            #expect(Self.scrollViews(in: sheet, at: .accessibility3).count == 1)
        }
    }
#endif
