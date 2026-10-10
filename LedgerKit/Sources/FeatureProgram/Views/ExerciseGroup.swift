import LedgerDesign
import SwiftUI

/// One superset, or one exercise on its own, as one block of hairline rows: each exercise under its own
/// rule, the open one's panel under its row, and one rule that closes the block. A superset's exercises
/// share the block, under "SUPERSET" over its note ("2 exercises back to back · rest after B"), drawn once.
/// The view reads no flag to find a superset and works out no letter: the model's groups are the blocks.
///
/// "SUPERSET" is grey, not orange (Pete's decision 1, A). VoiceOver reads the line as one heading,
/// "Superset", with the note as its value.
struct ExerciseGroup: View {
    let group: DayEditorModel.Group
    let send: (DayEditorAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            if let header = group.header {
                VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                    Eyebrow(header.title)
                    SectionNote(text: header.note)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(header.spokenLabel)
                .accessibilityValue(header.note)
            }
            HairlineList {
                ForEach(group.rows) { ExerciseRow(row: $0, send: send) }
            }
        }
    }
}
