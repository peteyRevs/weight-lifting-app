#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F10 S5, criterion 1: what exists only because the cover scrolls, on the real screen hosted at an iPhone
    /// 17's size. A live workout is its header pinned over one scroll view; what the page says is
    /// `WorkoutAccessibilityTests`', and the stops inside the real scroll view are the nightly UI test's.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @Suite("Workout screen", .serialized, .tags(.feature))
    struct WorkoutScreenTests {
        /// An iPhone 17's screen, the phone the references are drawn for.
        nonisolated static let phone = CGSize(width: SnapshotConfig.phoneWidth, height: 874)
        nonisolated static let workouts: [WorkoutPreview] = [.started, .minutes, .hour, .logging, .dropSet, .discarding]

        static func screen(_ preview: WorkoutPreview, send: @escaping (WorkoutAction) -> Void = { _ in }) -> some View {
            WorkoutScreen(model: preview.model, send: send)
                .environment(\.workoutTimeline, .fixed(at: preview.now))
                .frame(height: phone.height)
        }

        /// The scroll views under `view`, hosted in a window of the phone's size at `textSize`, in window
        /// coordinates.
        private static func scrollViews(
            in view: some View,
            at textSize: DynamicTypeSize
        ) -> [(frame: CGRect, content: CGSize)] {
            let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, textSize))
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            return found(in: host.view).map { ($0.convert($0.bounds, to: nil), $0.contentSize) }
        }

        private static func found(in view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(found(in:))
        }

        @Test("A live workout is one scroll view, as wide as the phone, under its header", arguments: workouts)
        func screen_isOneScrollViewUnderTheHeader(_ preview: WorkoutPreview) throws {
            let scrolls = Self.scrollViews(in: Self.screen(preview), at: .large)
            #expect(scrolls.count == 1)
            let scroll = try #require(scrolls.first)
            #expect(scroll.frame.width == Self.phone.width)
            #expect(scroll.content.width <= Self.phone.width, "it never scrolls sideways")
            // The header's five stops are outside the scroll view, and take no more height than the screen
            // has above it: the header is pinned over the page. (The reader's window is taller than the
            // phone and centres the screen, so the stops' own span is measured, not their place.)
            let header = Self.screen(preview).accessibilityElements(outsideScrollViews: true)
            #expect(header.count == 5)
            let top = try #require(header.map(\.frame.minY).min())
            let bottom = try #require(header.map(\.frame.maxY).max())
            #expect(bottom - top <= scroll.frame.minY, "the header spans \(bottom - top) pt above \(scroll.frame)")
            #expect(scroll.frame.height > Self.phone.height / 2, "the page takes the rest of the screen")
        }

        @Test(
            "The header pinned above the page reads as its table writes it, in place on the real screen",
            arguments: workouts
        )
        func screen_headerInPlace_isItsTree(_ preview: WorkoutPreview) throws {
            for appearance in WorkoutAccessibilityTests.appearances {
                let found = Self.screen(preview).accessibilityElements(appearance, outsideScrollViews: true).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                let expected = try Array(#require(WorkoutTrees.all[preview]).prefix(5))
                let difference = firstDifference(found: found, expected: expected)
                #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
            }
        }

        @Test("The header's buttons answer in place, above the scroll view")
        func screen_headerButtons_sendTheirActions() {
            var sent: [WorkoutAction] = []
            Self.screen(.logging) { sent.append($0) }.withAccessibilityElements(outsideScrollViews: true) { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent == [.minimize, .finish])
        }

        @Test("At the largest text size of the matrix the page is longer than the screen, and scrolls")
        func page_atAnAccessibilitySize_scrolls() throws {
            let scroll = try #require(Self.scrollViews(in: Self.screen(.logging), at: .accessibility3).first)
            #expect(scroll.content.height > scroll.frame.height + 100)
            #expect(scroll.content.width <= Self.phone.width)
        }

        @Test("Loading and the failed screen hold no scroll view", arguments: [WorkoutPreview.loading, .failed])
        func screen_withoutAWorkout_hasNoScrollView(_ preview: WorkoutPreview) {
            #expect(Self.scrollViews(in: Self.screen(preview), at: .large).isEmpty)
        }
    }
#endif
