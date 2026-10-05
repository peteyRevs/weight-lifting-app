#if os(iOS)
    @testable import FeatureOnboarding
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F08 S2, criterion 10: "going to another step starts that step at its top" (review S2-B1). The real root,
    /// hosted at an iPhone 17's size at the largest text size of the matrix, where every step is longer than the
    /// screen; its one scroll view is found under the hosting view, scrolled to its end, and the step changed
    /// through the store, as a tap on the pinned button changes it.
    @Suite("Onboarding scrolling", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct OnboardingScrollTests {
        /// The page's scroll view: how far it is from its top, and how far it can go.
        private struct Place {
            let view: UIScrollView
            let offset: CGFloat
            let range: CGFloat
        }

        private static func scroll(in view: UIView) throws -> Place {
            let found = Hosted.scrollViews(in: view)
            #expect(found.count == 1, "the screen is its pinned parts and one scroll view: \(found)")
            let scroll = try #require(found.first)
            let top = -scroll.adjustedContentInset.top
            let end = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
            return Place(view: scroll, offset: scroll.contentOffset.y - top, range: end - top)
        }

        /// Scrolls the page to its end, as a lifter reading down to the last row does.
        private static func scrollToTheEnd(of view: UIView) throws {
            let page = try scroll(in: view)
            #expect(page.range > 100, "control: at this text size the step is longer than the screen")
            let end = CGPoint(x: page.view.contentOffset.x, y: page.view.contentOffset.y - page.offset + page.range)
            page.view.setContentOffset(end, animated: false)
            Hosted.settle(view)
            #expect(try abs(scroll(in: view).offset - page.range) < 1, "control: the page is at its end")
        }

        @Test("Continue and Back start the next step at its top, wherever the last one was scrolled to")
        func stepChange_startsTheStepAtItsTop() async throws {
            try await StoreScene.run { scene in
                let root = OnboardingRoot(store: scene.store, prepareRetry: {})
                    .environment(\.dynamicTypeSize, .accessibility3)
                try await Hosted.view(root) { view in
                    for (action, step) in [
                        (OnboardingAction.advance, OnboardingState.Step.days), (.advance, .program), (.back, .days),
                        (.back, .goal)
                    ] {
                        try Self.scrollToTheEnd(of: view)
                        scene.store.send(action)
                        Hosted.settle(view)
                        #expect(scene.store.state.step == step)
                        let offset = try Self.scroll(in: view).offset
                        #expect(abs(offset) < 1, "\(step) opens \(offset) pt down")
                    }
                }
            }
        }

        /// An iPhone SE (2nd and 3rd generation): the narrowest and shortest phone iOS 26 runs on.
        nonisolated static let narrowest = CGSize(width: 375, height: 667)

        /// The height the pinned part of `model` needs at `width` and the largest text size, with nothing
        /// pressing on it.
        private static func pinnedHeight(_ model: OnboardingStepModel, width: CGFloat) -> CGFloat {
            let footer = OnboardingFooter(model: model) { _ in }.environment(\.dynamicTypeSize, .accessibility5)
            let unbounded = CGSize(width: width, height: .greatestFiniteMagnitude)
            return UIHostingController(rootView: footer).sizeThatFits(in: unbounded).height
        }

        @Test(
            "On the narrowest phone at the largest text size the pinned part keeps its full height (F8-S2-1)",
            arguments: [
                OnboardingState(step: .program, days: .six, units: .kg, phase: .failed),
                OnboardingState(phase: .failed), OnboardingState(step: .days)
            ]
        )
        func pinnedPart_onTheNarrowestPhone_isNotSqueezed(_ state: OnboardingState) async throws {
            let model = OnboardingPresentation.make(state, locale: Fixtures.locale)
            let whole = Self.pinnedHeight(model, width: Self.narrowest.width)
            let screen = OnboardingScreen(model: model) { _ in }.environment(\.dynamicTypeSize, .accessibility5)
            try await Hosted.view(screen, size: Self.narrowest) { view in
                let page = try Self.scroll(in: view).view
                let room = view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom
                if state.phase == .failed {
                    #expect(whole > room / 2, "control: here the pinned part needs more than half the screen")
                }
                let given = view.bounds.maxY - view.safeAreaInsets.bottom - page.convert(page.bounds, to: view).maxY
                #expect(given >= whole - 0.5, "the pinned part has \(given) pt of the \(whole) pt its text needs")
                #expect(page.bounds.height > 44, "and the page above it still has room to scroll in")
            }
        }

        @Test(
            "The pinned part keeps a gap to the screen's edge where the bottom safe area is smaller than the gap",
            arguments: [narrowest, Hosted.phone]
        )
        func pinnedPart_keepsAGapToTheEdge(on size: CGSize) async throws {
            let model = OnboardingPresentation.make(OnboardingState(), locale: Fixtures.locale)
            let whole = Self.pinnedHeight(model, width: size.width)
            let screen = OnboardingScreen(model: model) { _ in }.environment(\.dynamicTypeSize, .accessibility5)
            try await Hosted.view(screen, size: size) { view in
                let page = try Self.scroll(in: view).view
                let safeBottom = view.safeAreaInsets.bottom
                // Under the pinned part: what is left between it and the screen's bottom edge.
                let under = view.bounds.maxY - page.convert(page.bounds, to: view).maxY - whole
                #expect(abs(under - max(safeBottom, LedgerSpacing.m)) < 0.5, "\(under) pt, safe area \(safeBottom)")
            }
        }

        @Test("A pick on the same step leaves the page where the lifter scrolled it")
        func pick_keepsThePagesPlace() async throws {
            try await StoreScene.run { scene in
                let root = OnboardingRoot(store: scene.store, prepareRetry: {})
                    .environment(\.dynamicTypeSize, .accessibility3)
                try await Hosted.view(root) { view in
                    try Self.scrollToTheEnd(of: view)
                    let before = try Self.scroll(in: view).offset
                    scene.store.send(.pickGoal(.consistency))
                    Hosted.settle(view)
                    #expect(try abs(Self.scroll(in: view).offset - before) < 1)
                }
            }
        }
    }
#endif
