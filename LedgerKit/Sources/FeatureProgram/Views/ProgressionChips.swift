import LedgerDesign
import SwiftUI

/// "PROGRESSION", the section's heading; "Linear", "Double" and "Fixed" as pills that wrap; and under them
/// what the chosen progression does. The chosen pill is filled with ink, is read as selected and is not a
/// button: the model gives it no action, and a tap on it does nothing.
struct ProgressionChips: View {
    let model: SlotEditorModel.ProgressionPicker
    let send: (DayEditorAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(model.title)
            WrapLayout {
                ForEach(model.chips) { chip in
                    PillButton(chip.title, style: chip.isSelected ? .filled : .outline) {
                        if let action = chip.action {
                            send(action)
                        }
                    }
                    .allowsHitTesting(chip.action != nil)
                    .accessibilityRemoveTraits(chip.action == nil ? .isButton : [])
                    .accessibilityAddTraits(chip.action == nil ? .isStaticText : [])
                }
            }
            Text(model.note)
                .ledgerFont(.bodyLight)
                .foregroundStyle(LedgerColor.inkMuted)
        }
    }
}
