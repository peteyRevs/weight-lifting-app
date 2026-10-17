import LedgerDesign
import SwiftUI

/// "REMAINING" (v2): the exercises after the shown one, each with its sets and reps. A tap on a row shows
/// that exercise. Each row is one button, read as its name and its scheme. v2's small number before each
/// name is not drawn: `HairlineRow` has no leading column, and the header's segments already place the
/// exercise.
struct RemainingList: View {
    let model: RemainingModel
    let send: (WorkoutEdit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(model.title)
            HairlineList {
                ForEach(model.rows) { row in
                    HairlineRow(row.name, action: { send(.jump(exerciseIndex: row.exerciseIndex)) }, accessory: {
                        Text(row.scheme)
                            .ledgerFont(.caption)
                            .foregroundStyle(LedgerColor.inkMuted)
                    })
                    .accessibilityIdentifier("workout.remaining.row.\(row.exerciseIndex)")
                }
            }
        }
    }
}
