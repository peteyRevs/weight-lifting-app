#if os(iOS) && DEBUG
    @testable import FeatureProgram
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9, criterion 2, and S10, criterion 2: what exists only because the three screens scroll. Each
    /// screen, hosted at an iPhone 17's size, is one scroll view around its page; the builder pins nothing, the
    /// sheet pins its title, its search field and its foot around it, the Day editor its bar above it; and
    /// no page holds a scroll view of its own. What the pages say is
    /// `ProgramAccessibilityTests`'; the stops inside the real scroll views are the nightly UI tests of S13 and
    /// S14. (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @Suite("Program screens", .serialized, .tags(.feature))
    struct ProgramScreenTests {
        /// An iPhone 17's screen, the phone the references are drawn for.
        nonisolated static let phone = CGSize(width: SnapshotConfig.phoneWidth, height: 874)

        /// A scroll view as it was found: where it stood in the window, and the size of what it scrolls.
        struct Scroll {
            let frame: CGRect
            let contentSize: CGSize
        }

        /// The scroll views under `view`, hosted in a window of the phone's size at `textSize`. A one-line text
        /// field is no scroll view; a field of several lines would be, and would be counted.
        static func scrollViews(in view: some View, at textSize: DynamicTypeSize) -> [Scroll] {
            let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, textSize))
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            return found(in: host.view).map {
                Scroll(frame: $0.convert($0.bounds, to: host.view), contentSize: $0.contentSize)
            }
        }

        private static func found(in view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(found(in:))
        }

        @Test("In every state its screen is one scroll view, as wide as the phone", arguments: ProgramPreview.allCases)
        func screen_isOneScrollView(_ preview: ProgramPreview) {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let scrolls = Self.scrollViews(in: preview.content, at: size)
                #expect(scrolls.count == 1, "\(size)")
                #expect(scrolls.first.map { $0.frame.width <= Self.phone.width } ?? false)
                #expect(scrolls.first.map { $0.contentSize.width <= $0.frame.width } ?? false, "it scrolls sideways")
            }
        }

        @Test(
            "In every state the parts the trees and references are taken from hold no scroll view",
            arguments:
            ProgramPreview.allCases
        )
        func parts_holdNoScrollView(_ preview: ProgramPreview) {
            for size in [DynamicTypeSize.large, .accessibility3] {
                #expect(Self.scrollViews(in: ProgramParts(preview: preview), at: size).isEmpty, "\(size)")
            }
        }

        @Test("The builder scrolls from the top of the screen: nothing is pinned above its page")
        func builder_pinsNothing() throws {
            let scroll = try #require(Self.scrollViews(in: ProgramPreview.builder.content, at: .large).first)
            #expect(scroll.frame.width == Self.phone.width && scroll.frame.minX == 0)
            #expect(scroll.frame.height >= Self.phone.height - 100, "all but the safe areas: \(scroll.frame)")
            #expect(scroll.contentSize.height > Self.phone.height, "the seed program is longer than the screen")
        }

        @Test("The Day editor pins its bar alone: the page, with the day's name, scrolls under it")
        func dayEditor_barIsPinnedAboveItsPage() throws {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let scroll = try #require(Self.scrollViews(in: ProgramPreview.dayOpenLinear.content, at: size).first)
                // The bar is its two buttons: 44 pt and its padding at the default size, and no more than a
                // line of the largest text. The simulator's window keeps 62 pt above the screen.
                let bar = scroll.frame.minY - 62
                #expect(bar >= 44 && bar <= 110, "the bar is \(bar) pt high at \(size): \(scroll.frame)")
                #expect(scroll.frame.width == Self.phone.width && scroll.frame.minX == 0)
                #expect(scroll.contentSize.height > scroll.frame.height, "an open exercise is longer than the screen")
            }
        }

        @Test("The sheet's list scrolls between its pinned search field and its pinned foot")
        func sheet_listScrollsBetweenItsPinnedParts() throws {
            let sheet = ProgramPreview.library.content
            let scroll = try #require(Self.scrollViews(in: sheet, at: .accessibility3).first)
            let frame = scroll.frame
            #expect(frame.minY > 100, "the title and the search field stand above the list: \(frame)")
            #expect(frame.maxY < Self.phone.height - 54, "the foot's button stands under the list: \(frame)")
            #expect(scroll.contentSize.height > frame.height, "eight rows at an accessibility size scroll")
        }
    }
#endif
