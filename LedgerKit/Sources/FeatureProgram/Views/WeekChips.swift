import LedgerDesign
import SwiftUI

/// One chip per week of the block, in rows that wrap: eight weeks make two rows of four on an iPhone 17, and
/// no row scrolls sideways (the M1 convention: a page holds no scroll view).
///
/// A chip is a pill of two lines, "W3" over "4 DAYS". The selected week's is filled with ink, as a selected
/// filter pill is. A deload week's "DELOAD" is orange, the builder's one use of the accent (Pete's decision
/// 1, A), except on the selected chip: orange on the ink fill is below AA in both themes, so there it takes
/// the fill's own text colour and the week's title is the orange one (`WeekSection`).
///
/// VoiceOver reads a chip as "Week 3, 4 days", selected when it is.
struct WeekChips: View {
    let chips: [ProgramBuilderModel.WeekChip]
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        WrapLayout {
            // A week's place is its identity on screen.
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Button { send(chip.action) } label: { label(chip) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.spokenLabel)
                    .accessibilityValue(chip.spokenValue)
                    .accessibilityAddTraits(chip.isSelected ? .isSelected : [])
            }
        }
    }

    private func label(_ chip: ProgramBuilderModel.WeekChip) -> some View {
        VStack(spacing: LedgerSpacing.xs) {
            Text(chip.title)
                .ledgerFont(.numeralS)
                .foregroundStyle(chip.isSelected ? LedgerColor.ground : LedgerColor.ink)
            Text(chip.subtitle)
                .ledgerFont(.eyebrow)
                .foregroundStyle(subtitleColor(chip))
        }
        .padding(.horizontal, LedgerSpacing.l)
        .padding(.vertical, LedgerSpacing.s)
        .background {
            if chip.isSelected {
                Capsule.ledgerPill.fill(LedgerColor.ink)
            } else {
                Capsule.ledgerPill.strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
            }
        }
        .ledgerHitTarget()
    }

    private func subtitleColor(_ chip: ProgramBuilderModel.WeekChip) -> Color {
        if chip.isSelected {
            LedgerColor.ground
        } else if chip.isDeload {
            LedgerColor.accentText
        } else {
            LedgerColor.inkMuted
        }
    }
}
