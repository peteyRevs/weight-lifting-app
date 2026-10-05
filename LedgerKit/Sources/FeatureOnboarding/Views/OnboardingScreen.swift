import LedgerDesign
import SwiftUI

/// One step of onboarding, drawn from its model and nothing else (v2 `Onboarding`): its pinned part,
/// `OnboardingFooter`, under a scroll view around `OnboardingPage`. That is the screen's one layout at every
/// text size (the M1 convention for a screen that scrolls): where the page fits it does not move, and where it
/// does not, it scrolls under the buttons, which stay in reach.
///
/// The screen decides nothing and runs no task; `OnboardingRoot` runs the store's work around it. Two things
/// here exist only because the page scrolls:
/// - going to another step starts that step at its top, wherever the last one was scrolled to;
/// - on a phone with no bottom safe area (a home button) the pinned part keeps a gap to the screen's edge.
struct OnboardingScreen: View {
    let model: OnboardingStepModel
    let send: (OnboardingAction) -> Void
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    OnboardingPage(model: model, send: send)
                }
                .scrollPosition($position)
                .scrollBounceBehavior(.basedOnSize)
                OnboardingFooter(model: model, send: send)
                    .padding(.bottom, max(LedgerSpacing.m - proxy.safeAreaInsets.bottom, 0))
            }
        }
        .background(LedgerColor.ground)
        .onChange(of: model.step) {
            position.scrollTo(edge: .top)
        }
    }
}
