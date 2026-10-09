import LedgerDesign
import SwiftUI

/// Everything the exercise library sheet scrolls, and never a scroll view: the muscle chips, the equipment
/// chips, and under them the exercises that pass the filter as hairline rows, or, when none does, "Nothing
/// matches that filter." with "Clear filters" as an outlined pill.
struct ExercisePickerPage: View {
    let model: ExercisePickerModel
    let send: (ExercisePickerAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            VStack(alignment: .leading, spacing: LedgerSpacing.m) {
                FilterChips(row: model.muscles, send: send)
                FilterChips(row: model.equipment, send: send)
            }
            switch model.content {
            case let .rows(rows):
                HairlineList {
                    ForEach(rows) { ExercisePickerRow(row: $0, send: send) }
                }
            case let .nothingMatches(empty):
                VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                    Text(empty.message)
                        .ledgerFont(.bodyLight)
                        .foregroundStyle(LedgerColor.inkMuted)
                    PillButton(empty.clear.title) { send(empty.clear.action) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
