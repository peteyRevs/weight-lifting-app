import LedgerDesign
import SwiftUI

/// One step of onboarding, drawn from its model and nothing else (v2 `Onboarding`): "Back", the three bars, the
/// title and its line, then the picks or the program's days; under them, pinned to the bottom, the primary button
/// and "Skip setup", with the failure line above the button when a save has failed.
///
/// The page above the buttons is drawn as it is when it fits, as the prototype's fixed page, and scrolls only
/// when it does not (large text, a small screen): at any text size both buttons stay in reach and nothing is
/// cut.
///
/// Every control sends the action its model names; the screen decides nothing. It runs no task: previews,
/// snapshots and the VoiceOver test draw it as it is, and `OnboardingRoot` runs the store's work around it.
struct OnboardingScreen: View {
    let model: OnboardingStepModel
    let send: (OnboardingAction) -> Void
    /// VoiceOver moves to the title when the step changes: without it, focus stays on the button just pressed.
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                page
                ScrollView { page }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .background(LedgerColor.ground)
        .onChange(of: model.title) {
            isTitleFocused = true
        }
        .onChange(of: model.error) { _, error in
            // The line appears without a change of focus, so VoiceOver would not read it.
            if let error {
                AccessibilityNotification.Announcement(error).post()
            }
        }
    }

    /// Everything above the buttons.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            heading
            list
        }
        .padding(.horizontal, LedgerSpacing.screen)
        .padding(.bottom, LedgerSpacing.m)
    }

    /// "Back" over the bars. On step 1 the pill is hidden and keeps its place, so the bars stay where they are
    /// from step to step.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            PillButton(model.back.title, style: .ghost) { send(model.back.action) }
                .disabled(!model.canEdit)
                .accessibilityIdentifier("onboarding.back")
                .opacity(model.showsBack ? 1 : 0)
                .accessibilityHidden(!model.showsBack)
                .allowsHitTesting(model.showsBack)
            ProgressSegments(model.progress, label: model.progressLabel, value: "")
                .accessibilityIdentifier("onboarding.progress")
        }
        .padding(.bottom, LedgerSpacing.xxl)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            Text(model.title)
                .ledgerFont(.display)
                .foregroundStyle(LedgerColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .accessibilityIdentifier("onboarding.title")
            Text(model.body)
                .ledgerFont(.bodyLight)
                .foregroundStyle(LedgerColor.inkMuted)
        }
        .padding(.bottom, LedgerSpacing.xxl)
    }

    /// Steps 1 and 2: the picks, one button each. Step 3: the program's days, a list to read.
    private var list: some View {
        HairlineList {
            switch model.content {
            case let .options(options):
                ForEach(options) { option in
                    OnboardingOptionRow(option: option) { send(option.action) }
                }
                .disabled(!model.canEdit)
            case let .days(days):
                ForEach(days) { day in
                    HairlineRow(day.title, detail: day.detail)
                        .accessibilityIdentifier("onboarding.preview.\(day.id)")
                }
            }
        }
    }

    private var footer: some View {
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
        // Keeps a page that scrolls from touching the buttons where it is cut.
        .padding(.top, LedgerSpacing.m)
    }
}
