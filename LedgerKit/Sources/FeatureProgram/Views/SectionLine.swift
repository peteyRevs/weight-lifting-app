import LedgerDesign
import SwiftUI

/// A section's first line: its eyebrow, which is the section's heading, and whatever stands at the trailing
/// edge beside it (a short muted note, the block's "−" and "+"). At accessibility text sizes the trailing
/// part moves under the eyebrow, so neither has to squeeze.
struct SectionLine<Trailing: View>: View {
    let eyebrow: String
    var tint: Eyebrow.Tint = .muted
    @ViewBuilder let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LedgerSpacing.m))
        layout {
            Eyebrow(eyebrow, tint: tint)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

extension SectionLine where Trailing == SectionNote? {
    /// The eyebrow with a short muted note beside it ("Tap to assign", "4 days · 58 sets a week"); nil draws
    /// the eyebrow alone.
    init(eyebrow: String, tint: Eyebrow.Tint = .muted, note: String?) {
        self.init(eyebrow: eyebrow, tint: tint) { note.map(SectionNote.init) }
    }
}

/// The note of a section's first line.
struct SectionNote: View {
    let text: String

    var body: some View {
        Text(text)
            .ledgerFont(.caption)
            .foregroundStyle(LedgerColor.inkMuted) // the prototype's .38 is below AA
    }
}
