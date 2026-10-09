import LedgerDesign
import SwiftUI

/// The block: "BLOCK · 8 WEEKS" with "−" and "+" at the trailing edge, one chip per week under it, and under
/// the chips the notice, when the model carries one ("A block needs at least 2 weeks.").
///
/// "−" and "+" are the round outlined buttons of F06's stepper. To VoiceOver the two are one adjustable
/// element, "Block length, 8 weeks": a swipe up adds a week, a swipe down sends what "−" sends, which is the
/// notice when the last week cannot go. The notice is ink on the ground, not orange (Pete's decision 1, A).
struct BlockSection: View {
    let model: ProgramBuilderModel.Block
    let notice: String?
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            SectionLine(eyebrow: model.title) { lengthStepper }
            WeekChips(chips: model.chips, send: send)
            if let notice {
                Text(notice)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkSecondary)
            }
        }
    }

    private var lengthStepper: some View {
        HStack(spacing: LedgerSpacing.s) {
            // The buttons' own labels are never read: the pair is one element, labelled below.
            IconPillButton(model.spokenLabel, icon: .minus) { send(model.removeWeek) }
            IconPillButton(model.spokenLabel, icon: .plus) { send(model.addWeek) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spokenLabel)
        .accessibilityValue(model.spokenValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: send(model.addWeek)
            case .decrement: send(model.removeWeek)
            @unknown default: break
            }
        }
    }
}
