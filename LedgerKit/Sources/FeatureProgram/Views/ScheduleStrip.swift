import LedgerDesign
import SwiftUI

/// The selected week's seven weekdays, each a cell with the weekday's letter over the tag of the day it
/// trains, or "REST". A tap assigns the next day of the cycle. A training day's cell is filled with the quiet
/// fill and its tag is ink; a rest day's is an outline and its word is muted.
///
/// The cells are always of one width, and no word is ever cut (`EqualCells`): the seven stand in one row while
/// the widest of them fits a seventh of it, and in rows of as many as fit otherwise (the larger text sizes,
/// a long tag). The targets touch, and what is drawn stands `xs` inside each, so the strip is set `xs` out
/// on both sides to keep the drawn cells on the page's edges. A cell's target is then at least 44 pt wide on
/// every iPhone: a seventh of the narrowest, 375 pt, is 47 pt, and a wrapped cell is wider than a seventh.
///
/// VoiceOver reads a cell as "Tuesday, Rest" with the model's hint. In a program with no training day a cell
/// offers nothing and is read as text.
struct ScheduleStrip: View {
    let cells: [ProgramBuilderModel.Cell]
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        EqualCells {
            ForEach(cells, id: \.weekday) { ScheduleCell(cell: $0, send: send) }
        }
        .padding(.horizontal, -LedgerSpacing.xs)
    }
}

/// One weekday of the strip. It takes the width it is given; its own width is its words' and the `xs` around
/// what is drawn, with no room beside the words and no least width: both are `EqualCells`' to give, which
/// could not tell a cell that is 44 pt wide for its words from one that is so for its target. Its two lines
/// and their padding make it higher than 44 pt at every text size.
private struct ScheduleCell: View {
    let cell: ProgramBuilderModel.Cell
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        if let action = cell.action {
            // The model gives a hint with every action; without one nothing more is read.
            let hint: String = cell.spokenHint ?? .init()
            Button { send(action) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel(cell.spokenLabel)
                .accessibilityValue(cell.spokenValue)
                .accessibilityHint(hint)
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
        // A letter and a tag are one word each; `EqualCells` never gives a cell less than its words take.
        .lineLimit(1)
        .padding(.vertical, LedgerSpacing.m)
        .frame(maxWidth: .infinity)
        .background {
            if cell.isRest {
                Capsule.ledgerPill.strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
            } else {
                Capsule.ledgerPill.fill(LedgerColor.hairline)
            }
        }
        .padding(LedgerSpacing.xs)
        .contentShape(Rectangle())
    }
}

/// Children in cells of one width, none narrower than the widest child's own width, so no child is ever
/// squeezed: in one row while that leaves each child at least `tightRoom` beside its content, and otherwise
/// in rows of as many cells as fit with `wrappedRoom` each. Either way the cells share the whole width; a
/// last row that is not full starts at the leading edge. Every row is as high as the highest child. With no
/// width proposed, everything stands on one row at the widest child's width.
///
/// The one row is kept as long as it can be: a strip of seven reads as a week, and two rows do not.
private nonisolated struct EqualCells: Layout {
    /// The least room a cell has beside its child in the one row, both sides together.
    static let tightRoom = LedgerSpacing.xs
    /// The least room a cell has beside its child once the row has wrapped: as much as a pill gives its title.
    static let wrappedRoom = LedgerSpacing.xl

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrangement(of: subviews, in: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let arrangement = arrangement(of: subviews, in: bounds.width)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(arrangement.cell)
            )
        }
    }

    /// Where each child's cell stands, the cells' one size, and the size they take together.
    private struct Arrangement {
        var size = CGSize.zero
        let cell: CGSize
        var origins: [CGPoint] = []
    }

    private func arrangement(of subviews: Subviews, in width: CGFloat?) -> Arrangement {
        var widest: CGFloat = 0
        var highest: CGFloat = 0
        for size in subviews.map({ $0.sizeThatFits(.unspecified) }) {
            widest = size.width > widest ? size.width : widest
            highest = size.height > highest ? size.height : highest
        }
        let cellWidth = cellWidth(for: subviews, widest: widest, in: width)
        var arrangement = Arrangement(cell: CGSize(width: cellWidth, height: highest))
        var next = CGPoint.zero
        for _ in subviews {
            // A cell whose child would pass the trailing edge starts a row. A cell is wider than its child
            // by its room, so what the sum of the cells' widths loses to rounding starts none.
            if let width, width.isFinite, next.x > 0, next.x + widest > width {
                next = CGPoint(x: 0, y: next.y + highest)
            }
            arrangement.origins.append(next)
            next.x += cellWidth
            arrangement.size.width = next.x > arrangement.size.width ? next.x : arrangement.size.width
            arrangement.size.height = next.y + highest
        }
        return arrangement
    }

    /// The cells' width: the same share of `width` for all, in the one row or in rows of as many as fit.
    private func cellWidth(for subviews: Subviews, widest: CGFloat, in width: CGFloat?) -> CGFloat {
        guard let width, width.isFinite, widest > 0 else {
            return widest
        }
        // The one row, when every cell has its tight room in it: the width over the number of cells, which
        // is the row's least width over one cell's.
        let tight = widest + Self.tightRoom
        var row: CGFloat = 0
        for _ in subviews {
            row += tight
        }
        if row <= width {
            return width * tight / row
        }
        // Rows of as many roomy cells as fit; when not even one does, a cell is the whole width.
        let roomy = widest + Self.wrappedRoom
        var fitting: CGFloat = 0
        for _ in subviews where fitting + roomy <= width {
            fitting += roomy
        }
        return fitting > 0 ? width * roomy / fitting : width
    }
}
