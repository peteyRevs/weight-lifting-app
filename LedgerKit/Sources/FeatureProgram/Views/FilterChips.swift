import LedgerDesign
import SwiftUI

/// One row of the library's filter chips: `LedgerDesign`'s `FilterChipRow` over the model's chips (moved there for
/// F12's Library). Each chip is read with its row's name ("Muscle: Chest"), since both rows have an "All".
struct FilterChips: View {
    let row: ExercisePickerModel.ChipRow
    let send: (ExercisePickerAction) -> Void

    var body: some View {
        FilterChipRow(row.chips, title: \.title, spokenLabel: \.spokenLabel, isSelected: \.isSelected) { chip in
            send(chip.action)
        }
    }
}
