import SwiftUI

/// One number on a watch summary (LedgerWatch "Workout done": "12/15 SETS", "24,180 LB MOVED"): the
/// value in the watch's stat numerals over an uppercase caption. `isHighlighted` draws the value
/// orange, as the prototype does for new PRs. A value too wide for its column shrinks, never below
/// the 11 pt watch floor; the caption wraps.
///
/// VoiceOver reads the block as one element: `accessibilitySummary` if given ("12 of 15 sets"), else
/// the value and caption ("12/15, Sets"). Strings are shown as given; features pass copy from their
/// catalog.
public struct WatchStatBlock: View {
    private let value: String
    private let caption: String
    private let isHighlighted: Bool
    private let summary: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ value: String, caption: String, isHighlighted: Bool = false, accessibilitySummary: String? = nil) {
        self.value = value
        self.caption = caption
        self.isHighlighted = isHighlighted
        summary = accessibilitySummary
    }

    public var body: some View {
        let size = LedgerFont.scaledSize(.watchStat, dynamicTypeSize: dynamicTypeSize)
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Text(value)
                .ledgerFont(.watchStat)
                .foregroundStyle(isHighlighted ? LedgerColor.accent : LedgerColor.watchInk)
                .lineLimit(1)
                .minimumScaleFactor(LedgerFont.shrinkLimit(.watchStat, size: size))
            Text(caption)
                .ledgerFont(.watchCaption)
                .foregroundStyle(LedgerColor.watchInkMuted) // the prototype's .40 is below AA
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: summary ?? "\(value), \(caption)"))
    }
}

/// The summary's four numbers, two by two as the prototype sets them, for the preview, the snapshot
/// tests and the gallery.
struct WatchStatBlockGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            HStack(alignment: .top, spacing: LedgerSpacing.m) {
                WatchStatBlock("12/15", caption: "Sets")
                WatchStatBlock("24,180", caption: "Lb moved")
            }
            HStack(alignment: .top, spacing: LedgerSpacing.m) {
                WatchStatBlock("142", caption: "Avg BPM")
                WatchStatBlock("2", caption: "New PR", isHighlighted: true)
            }
        }
    }
}
