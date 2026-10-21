@testable import FeatureOnboarding
import LedgerDesign
import LedgerTestSupport
import SwiftUI

/// A step's page followed by its pinned part, without the scroll view the screen puts the page in: what the
/// VoiceOver trees and the snapshot references are taken from (the M1 convention for a screen that scrolls,
/// `docs/testing-strategy.md` §2.6). The hosted reader cannot see inside a scroll view, and a scroll view has no
/// height of its own to be drawn at.
struct OnboardingParts: View {
    let model: OnboardingStepModel
    var send: (OnboardingAction) -> Void = { _ in }

    /// The parts of `state`, as the presentation models it in the tests' locale.
    init(_ state: OnboardingState, send: @escaping (OnboardingAction) -> Void = { _ in }) {
        model = OnboardingPresentation.make(state, locale: Fixtures.locale)
        self.send = send
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPage(model: model, send: send)
            OnboardingFooter(model: model, send: send)
        }
        .background(LedgerColor.ground)
    }
}
