import LedgerDesign
import SwiftUI

/// One row of filter chips, pills that wrap: the chosen one filled with ink, which VoiceOver hears as
/// selected, the others outlined. Each is read with its row's name ("Muscle: Chest"), since both rows have
/// an "All".
struct FilterChips: View {
    let row: ExercisePickerModel.ChipRow
    let send: (ExercisePickerAction) -> Void

    var body: some View {
        WrapLayout(lineSpacing: 0) {
            ForEach(row.chips) { chip in
                PillButton(chip.title, style: chip.isSelected ? .filled : .outline) { send(chip.action) }
                    .accessibilityLabel(chip.spokenLabel)
            }
        }
    }
}
