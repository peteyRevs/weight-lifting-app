import LedgerDesign
import SwiftUI

/// The selected week's seven weekdays, each a cell with the weekday's letter over the tag of the day it
/// trains, or "REST". A tap assigns the next day of the cycle. A training day's cell is filled with the quiet
/// fill and its tag is ink; a rest day's is an outline and its word is muted.
///
/// The seven stand in one row, sharing its width, while they fit; when they do not (the accessibility text
/// sizes) they wrap at their own widths. A cell's target is at least 44 pt on a 375 pt phone as well: the
/// targets touch, and what is drawn stands `xs` inside each, so the strip is set `xs` out on both sides to
/// keep the drawn cells on the page's edges.
///
/// VoiceOver reads a cell as "Tuesday, Rest" with the model's hint. In a program with no training day a cell
/// offers nothing and is read as text.
struct ScheduleStrip: View {
    let cells: [ProgramBuilderModel.Cell]
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(cells, id: \.weekday) { ScheduleCell(cell: $0, fillsItsShare: true, send: send) }
            }
            WrapLayout(spacing: 0, lineSpacing: 0) {
                ForEach(cells, id: \.weekday) { ScheduleCell(cell: $0, fillsItsShare: false, send: send) }
            }
        }
        .padding(.horizontal, -LedgerSpacing.xs)
    }
}

/// One weekday of the strip.
private struct ScheduleCell: View {
    let cell: ProgramBuilderModel.Cell
    /// In the row a cell takes its share of the width; wrapped, its own.
    let fillsItsShare: Bool
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        if let action = cell.action {
            Button { send(action) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel(cell.spokenLabel)
                .accessibilityValue(cell.spokenValue)
                .spokenHint(cell.spokenHint)
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(cell.spokenLabel)
                .accessibilityValue(cell.spokenValue)
        }
    }

    private var label: some View {
        VStack(spacing: LedgerSpacing.s) {
            Text(cell.letter)
                .ledgerFont(.caption)
                .foregroundStyle(LedgerColor.inkMuted)
            Text(cell.label)
                .ledgerFont(.caption)
                .foregroundStyle(cell.isRest ? LedgerColor.inkMuted : LedgerColor.ink)
        }
        .lineLimit(1)
        .padding(.horizontal, LedgerSpacing.xs)
        .padding(.vertical, LedgerSpacing.m)
        .frame(maxWidth: fillsItsShare ? .infinity : nil)
        .background {
            if cell.isRest {
                Capsule.ledgerPill.strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
            } else {
                Capsule.ledgerPill.fill(LedgerColor.hairline)
            }
        }
        .padding(LedgerSpacing.xs)
        .ledgerHitTarget()
    }
}

private extension View {
    /// The hint VoiceOver reads after the element, when the model carries one.
    @ViewBuilder
    func spokenHint(_ hint: String?) -> some View {
        if let hint {
            accessibilityHint(hint)
        } else {
            self
        }
    }
}
