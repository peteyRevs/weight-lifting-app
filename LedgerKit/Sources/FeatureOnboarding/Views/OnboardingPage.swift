import LedgerDesign
import SwiftUI

/// Everything of a step that scrolls (v2 `Onboarding`): "Back", the three bars, the title and its line, then
/// the picks or the program's days. It never holds a scroll view: `OnboardingScreen` puts it in one, and the
/// snapshots and the VoiceOver trees are taken from it as it is (the M1 convention for a screen that scrolls,
/// `docs/testing-strategy.md` §2.6).
///
/// Every control sends the action its model names; the page decides nothing.
struct OnboardingPage: View {
    let model: OnboardingStepModel
    let send: (OnboardingAction) -> Void
    /// VoiceOver moves to the title when the step changes: without it, focus stays on the button just pressed.
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            heading
            list
        }
        .padding(.horizontal, LedgerSpacing.screen)
        .padding(.bottom, LedgerSpacing.m)
        .onChange(of: model.step) {
            isTitleFocused = true
        }
    }

    /// "Back" over the bars, its word flush with the edge the bars and the title start at. On step 1 the pill
    /// is hidden and keeps its place, so the bars stay where they are from step to step.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            PillButton(model.back.title, style: .ghost, flush: .leading) { send(model.back.action) }
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
}
