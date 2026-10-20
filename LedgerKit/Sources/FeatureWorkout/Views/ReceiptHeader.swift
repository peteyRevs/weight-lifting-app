import LedgerDesign
import SwiftUI

/// The receipt's pinned header (v1 "Session receipt"): the day the workout started over its name, a
/// heading, and "Done" at the trailing edge, which closes the cover onto Today. At accessibility text
/// sizes "Done" stands under the name, so the name keeps the full width. "Done" is ink, not orange: the
/// receipt has no orange control (F10 S7b, criterion 35).
struct ReceiptHeader: View {
    let model: ReceiptHeaderModel
    let send: (WorkoutAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LedgerSpacing.m))
        layout {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.date)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.title)
                    .ledgerFont(.heading)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PillButton(model.done) { send(.done) }
                .accessibilityIdentifier("workout.receipt.done")
        }
    }
}
