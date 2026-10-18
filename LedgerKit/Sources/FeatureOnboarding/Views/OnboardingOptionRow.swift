import LedgerDesign
import SwiftUI

/// One pick of steps 1 and 2 (v2 `Onboarding`): its label, a line under it and, when picked, the orange check,
/// under a hairline as a `HairlineRow` is drawn. The feature draws its own row because the selected trait must
/// sit on the button itself, and the label's ink follows the pick; `HairlineRow` offers neither.
///
/// VoiceOver reads the row as one button, "{title}, {detail}", selected when picked: the check is the visible
/// cue, a glyph and not colour alone. The check keeps its place when it is not drawn, so picking another row
/// never rewraps a label.
struct OnboardingOptionRow: View {
    let option: OnboardingStepModel.Option
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()
            Button(action: action) {
                HStack(spacing: LedgerSpacing.m) {
                    VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                        Text(option.title)
                            .ledgerFont(.body)
                            .foregroundStyle(option.isSelected ? LedgerColor.ink : LedgerColor.inkSecondary)
                        Text(option.detail)
                            .ledgerFont(.label)
                            .foregroundStyle(LedgerColor.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LedgerIconView(.check, sizedAs: .subheading)
                        .foregroundStyle(LedgerColor.accentText)
                        .opacity(option.isSelected ? 1 : 0)
                }
                .multilineTextAlignment(.leading)
                .padding(.vertical, LedgerSpacing.l)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(option.isSelected ? .isSelected : [])
            .accessibilityIdentifier("onboarding.option.\(option.id)")
        }
    }
}
