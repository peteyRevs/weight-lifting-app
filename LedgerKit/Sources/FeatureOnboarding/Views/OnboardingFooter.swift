import LedgerDesign
import SwiftUI

/// The part of the screen that does not scroll (v2 `Onboarding`): the primary button and "Skip setup", with the
/// failure sentence above the button when a save has failed. `OnboardingScreen` pins it under the page.
///
/// It always takes the height its text needs. A pinned part that could be squeezed gives up lines of its text
/// first: on the narrowest phone at the largest text size the failure sentence lost its third line to an
/// ellipsis (test finding F8-S2-1). The page above it scrolls, so it is the page that gives way.
struct OnboardingFooter: View {
    let model: OnboardingStepModel
    let send: (OnboardingAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error {
                Text(error)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, LedgerSpacing.m)
                    .accessibilityIdentifier("onboarding.error")
            }
            PrimaryButton(model.primary.title) { send(model.primary.action) }
                .accessibilityIdentifier("onboarding.cta")
            PillButton(model.skip.title, style: .ghost) { send(model.skip.action) }
                .accessibilityIdentifier("onboarding.skip")
        }
        .disabled(!model.canProceed)
        .padding(.horizontal, LedgerSpacing.screen)
        // Keeps the page from touching the buttons where it is cut.
        .padding(.top, LedgerSpacing.m)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.error) { _, error in
            // The sentence appears without a change of focus, so VoiceOver would not read it.
            if let error {
                AccessibilityNotification.Announcement(error).post()
            }
        }
    }
}
