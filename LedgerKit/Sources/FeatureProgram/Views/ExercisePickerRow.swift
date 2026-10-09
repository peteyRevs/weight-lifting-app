import LedgerDesign
import SwiftUI

/// One exercise of the library, F06's hairline row as one button: its name, the line "Machine · Back" (with
/// " · already in this day" when the day holds it, in the line's own grey), and at the trailing edge a mark
/// that says whether it is picked. A tap picks it, or takes it out of the picks.
///
/// VoiceOver reads the name with the line as its value, and the row as selected when it is picked; the mark
/// is not read.
struct ExercisePickerRow: View {
    let row: ExercisePickerModel.Row
    let send: (ExercisePickerAction) -> Void

    var body: some View {
        HairlineRow(row.name, detail: row.line) { send(row.action) } accessory: {
            PickMark(isPicked: row.isPicked)
        }
        .accessibilityLabel(row.name)
        .accessibilityValue(row.line)
        .accessibilityAddTraits(row.isPicked ? .isSelected : [])
    }
}

/// A row's mark: a plus in an outlined circle on an exercise that can be picked, a check on a circle filled
/// with ink on one that is, as a selected pill is filled.
private struct PickMark: View {
    let isPicked: Bool

    var body: some View {
        LedgerIconView(isPicked ? .check : .plus, sizedAs: .body)
            .foregroundStyle(isPicked ? LedgerColor.ground : LedgerColor.inkSecondary)
            .padding(LedgerSpacing.s)
            .background {
                if isPicked {
                    Circle().fill(LedgerColor.ink)
                } else {
                    Circle().strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
                }
            }
    }
}
