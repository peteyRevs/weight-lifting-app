import LedgerDesign
import SwiftUI

/// A card's first line (v2 "UP NEXT" with "Week 3 of 8 · ~52 min" at the trailing edge, on one baseline): the
/// eyebrow, which is the card's heading, and a short muted note beside it. At accessibility text sizes the note
/// moves under the eyebrow, so neither has to squeeze.
struct CardEyebrowLine: View {
    let eyebrow: String
    var tint: Eyebrow.Tint = .muted
    /// "Week 1 of 8 · ~38 min", "24:22"; nil draws the eyebrow alone.
    let note: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LedgerSpacing.m))
        layout {
            Eyebrow(eyebrow, tint: tint)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let note {
                Text(note)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted) // the prototype's .38 is below AA
            }
        }
    }
}
