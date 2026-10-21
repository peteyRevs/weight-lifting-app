@testable import FeatureOnboarding
import LedgerDesign
import LedgerTestSupport
import SwiftUI

// F08 S2 close-out: the convention for a screen that scrolls (testing-strategy §2.6). The screen is its pinned
// part plus `ScrollView { OnboardingPage }`, and a hosted reader cannot see inside a scroll view, so what a test
// reads or measures element by element is the page followed by the pinned part, without the scroll view.

/// A step's page followed by its pinned part, as the screen stacks them, without the scroll view.
struct AdversarialParts: View {
    let model: OnboardingStepModel
    let send: (OnboardingAction) -> Void

    init(model: OnboardingStepModel, send: @escaping (OnboardingAction) -> Void = { _ in }) {
        self.model = model
        self.send = send
    }

    /// The parts of `state`, as the presentation models it in the tests' locale.
    init(_ state: OnboardingState, send: @escaping (OnboardingAction) -> Void = { _ in }) {
        self.init(model: OnboardingPresentation.make(state, locale: Fixtures.locale), send: send)
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPage(model: model, send: send)
            OnboardingFooter(model: model, send: send)
        }
        .background(LedgerColor.ground)
    }
}

/// The page and the pinned part on a live store, given what `OnboardingRoot` gives its screen (`store.model`
/// and `store.send`), without the scroll view and without the root's tasks: a tap on any of its controls
/// reaches the store, and what the store then shows is drawn.
struct AdversarialStoreParts: View {
    let store: OnboardingStore

    var body: some View {
        AdversarialParts(model: store.model, send: store.send)
    }
}
