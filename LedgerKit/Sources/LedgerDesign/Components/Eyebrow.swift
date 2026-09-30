import SwiftUI

/// A small uppercase section label (v2: "UP NEXT" in orange; "RECENT", "REMAINING" muted).
/// VoiceOver treats it as a heading, so the rotor can jump between sections.
public struct Eyebrow: View {
    public nonisolated enum Tint: Sendable {
        /// The prototype's .32 ink, raised to `inkMuted` for AA: a section label carries meaning.
        case muted
        /// The live or next thing; orange text that reads on paper too (`accentText`).
        case accent
    }

    private let text: String
    private let tint: Tint

    public init(_ text: String, tint: Tint = .muted) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .ledgerFont(.eyebrow)
            .foregroundStyle(tint == .accent ? LedgerColor.accentText : LedgerColor.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Both tints, for the preview, the snapshot tests and the gallery.
struct EyebrowGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            Eyebrow("Up next", tint: .accent)
            Eyebrow("Recent")
            Eyebrow("Estimated 1RM · 8 weeks")
        }
    }
}
