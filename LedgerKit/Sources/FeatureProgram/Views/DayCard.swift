import LedgerDesign
import SwiftUI

/// One training day, a row of the hairline list and one button that opens the Day editor: the day's tag as
/// the schedule strip draws a training day's cell, its name, the line "5 exercises · 18 sets · ~39 min", the
/// short names of its first exercises as small outlined chips, and a chevron. The tag's pill is at least
/// three and a half ems wide, so that "UA" and "LB" take the same room and the names start on one line.
///
/// VoiceOver reads the row as the day's name with the line as its value; the chips are not read. At
/// accessibility text sizes the tag stands over the name and the row has no chevron, as Today's rows.
struct DayCard: View {
    let model: ProgramBuilderModel.DayCard
    let send: (ProgramBuilderAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The least width of the tag's pill, in ems of its text: two capitals and the pill's padding.
    static let tagEms: CGFloat = 3.5

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()
            Button { send(model.action) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(model.spokenLabel)
                .accessibilityValue(model.spokenValue)
        }
    }

    private var content: some View {
        let isLargeText = dynamicTypeSize.isAccessibilitySize
        let layout = isLargeText
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LedgerSpacing.m))
        return layout {
            Text(model.tag)
                .ledgerFont(.caption)
                .foregroundStyle(LedgerColor.ink)
                .padding(.horizontal, LedgerSpacing.s)
                .padding(.vertical, LedgerSpacing.xs)
                .frame(minWidth: LedgerFont.scaledSize(.caption, dynamicTypeSize: dynamicTypeSize) * Self.tagEms)
                .background(LedgerColor.hairline, in: .ledgerPill)
            VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                Text(model.name)
                    .ledgerFont(.body)
                    .foregroundStyle(LedgerColor.ink)
                Text(model.meta)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
                if !model.chips.isEmpty {
                    chips.padding(.top, LedgerSpacing.xs)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isLargeText {
                LedgerIconView(.chevron, sizedAs: .body).foregroundStyle(LedgerColor.inkMuted)
            }
        }
        .padding(.vertical, LedgerSpacing.l)
        .contentShape(Rectangle())
    }

    private var chips: some View {
        WrapLayout(spacing: LedgerSpacing.xs, lineSpacing: LedgerSpacing.xs) {
            // A chip is identified by its place: two can read the same.
            ForEach(Array(model.chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .ledgerFont(.eyebrow)
                    .foregroundStyle(LedgerColor.inkSecondary)
                    .padding(.horizontal, LedgerSpacing.s)
                    .padding(.vertical, LedgerSpacing.xs)
                    .background {
                        Capsule.ledgerPill.strokeBorder(LedgerColor.hairline, lineWidth: LedgerHairline.width)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
