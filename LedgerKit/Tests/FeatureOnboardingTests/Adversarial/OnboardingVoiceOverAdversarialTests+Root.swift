#if os(iOS)
    @testable import FeatureOnboarding
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// The page and the pinned part on a live store, and the hosted root (round 1's one test of the root, split
    /// in two by the convention: the root's page is inside its scroll view, where no reader can activate it).
    extension OnboardingVoiceOverAdversarialTests {
        @Test("The page and the pinned part on a live store answer every tap: picks, steps, one attempt")
        func partsOnAStore_taps_reachTheStore() throws {
            let scene = try AdversarialScene(.seeded())
            let parts = AdversarialStoreParts(store: scene.store)
            func said(_ elements: [Element]) -> [String] {
                elements.map { "\($0.label) | \($0.value) | \($0.traits.rawValue)" }
            }
            #expect(said(parts.accessibilityElements()) == said(Self.screen(OnboardingState()).accessibilityElements()))
            parts.withLiveAccessibilityElements { read in
                @MainActor
                func tap(_ label: String) {
                    _ = read().first { $0.accessibilityLabel == label }?.accessibilityActivate()
                }
                tap("Get stronger, Low reps, linear load increases")
                tap(BriefCopy.continueTitle)
                tap("6 days, Body-part split")
                tap(BriefCopy.back)
                #expect(scene.store.state == OnboardingState(step: .goal, goal: .strength, days: .six))
                tap(BriefCopy.continueTitle)
                tap(BriefCopy.continueTitle)
                let labels = read().map { $0.accessibilityLabel ?? "" }
                #expect(labels.contains("Body-Part Split, 8 weeks, pounds. Editable any time."), "\(labels)")
                tap(BriefCopy.startTraining)
                let attempt = scene.store.attempt
                tap(BriefCopy.startTraining)
                tap(BriefCopy.skipSetup)
                tap(BriefCopy.back)
                #expect(scene.store.attempt == attempt)
                #expect(attempt?.goal == .strength)
                #expect(attempt?.days == .six)
                #expect(scene.store.state.step == .program)
            }
        }

        @Test("The hosted root's pinned buttons reach its store, and its page cannot be read by accident")
        func root_pinnedButtons_reachItsStore() throws {
            let scene = try AdversarialScene(.seeded())
            let root = OnboardingRoot(store: scene.store, prepareRetry: {})
            // Read as a page would be, the root fails the read: it holds the scroll view.
            withKnownIssue {
                _ = root.accessibilityElements()
            } matching: { $0.description.contains("cannot see inside a scroll view") }
            // Read for what stands outside the scroll view, it gives its two pinned buttons, and they answer.
            root.withLiveAccessibilityElements(outsideScrollViews: true) { read in
                @MainActor
                func labels() -> [String] {
                    read().map { $0.accessibilityLabel ?? "" }
                }
                @MainActor
                func tap(_ label: String) {
                    _ = read().first { $0.accessibilityLabel == label }?.accessibilityActivate()
                }
                #expect(labels() == [BriefCopy.continueTitle, BriefCopy.skipSetup])
                tap(BriefCopy.continueTitle)
                #expect(scene.store.state.step == .days)
                tap(BriefCopy.continueTitle)
                #expect(scene.store.state.step == .program)
                #expect(labels() == [BriefCopy.startTraining, BriefCopy.skipSetup])
                tap(BriefCopy.startTraining)
                let attempt = scene.store.attempt
                tap(BriefCopy.startTraining)
                tap(BriefCopy.skipSetup)
                #expect(scene.store.attempt == attempt)
                #expect(attempt == OnboardingSaveAttempt(number: 1, goal: .both, days: .four))
                #expect(read().allSatisfy { $0.accessibilityTraits.contains(.notEnabled) })
            }
        }
    }
#endif
