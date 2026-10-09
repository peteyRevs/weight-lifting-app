import SwiftUI

/// Children run along a row at their own sizes and wrap onto the next row when the row is full: filter
/// chips, week chips, any run of pills that must not scroll sideways. Rows start at the leading edge, so
/// under a right-to-left layout they run from the right (SwiftUI mirrors a layout's placements).
///
/// A child wider than the row is given the row's width, and takes a row to itself. Children of one row are
/// centred on the row's height. With no width proposed, everything stands on one row. The size the layout
/// reports is the size it places its children in.
public nonisolated struct WrapLayout: Layout {
    /// Between two children of a row.
    public var spacing: CGFloat
    /// Between two rows.
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = LedgerSpacing.s, lineSpacing: CGFloat = LedgerSpacing.s) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrangement(of: sizes(of: subviews, in: proposal.width), in: proposal.width).size
    }

    public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let frames = arrangement(of: sizes(of: subviews, in: bounds.width), in: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Each child's own size; a child wider than `width` is asked again for its size at that width, so a
    /// label that wraps reports the height it then needs.
    ///
    /// The layout is measured at the width it is proposed and places at the width it reported, which for a
    /// row of one over-wide child is that child's fitted width, not the proposed one. The two agree as long
    /// as a child asked again at its own fitted width answers with the same size, as `Text` does; a child
    /// that answers otherwise would be placed at a size the layout did not report. A width of zero, SwiftUI's
    /// probe for the smallest size, gives every child a row to itself and no width.
    private func sizes(of subviews: Subviews, in width: CGFloat?) -> [CGSize] {
        subviews.map { subview in
            let own = subview.sizeThatFits(.unspecified)
            guard let width, width.isFinite, own.width > width else {
                return own
            }
            let fitted = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            return CGSize(width: min(fitted.width, width), height: fitted.height)
        }
    }

    /// Where children of these sizes stand in a row `width` wide, and the size they take together: the
    /// widest row by the rows' heights with the spacings between them. Without a finite width there is
    /// one row. A child goes onto the next row when it does not fit beside the ones before it; the first of
    /// a row always stays, whatever its width.
    func arrangement(of sizes: [CGSize], in width: CGFloat?) -> (size: CGSize, frames: [CGRect]) {
        let limit = width.flatMap { $0.isFinite ? $0 : nil } ?? .infinity
        var frames: [CGRect] = []
        var row: [CGRect] = []
        var top: CGFloat = 0
        var widest: CGFloat = 0

        /// Centres the open row's children on its height, and starts the next row under it.
        func closeRow() {
            let height = row.map(\.height).max() ?? 0
            frames += row.map { $0.offsetBy(dx: 0, dy: (height - $0.height) / 2) }
            widest = max(widest, row.last?.maxX ?? 0)
            top += height + lineSpacing
            row = []
        }

        for size in sizes {
            var leading = row.last.map { $0.maxX + spacing } ?? 0
            if !row.isEmpty, leading + size.width > limit {
                closeRow()
                leading = 0
            }
            row.append(CGRect(origin: CGPoint(x: leading, y: top), size: size))
        }
        closeRow()
        let height = frames.isEmpty ? 0 : top - lineSpacing
        return (CGSize(width: widest, height: height), frames)
    }
}

/// Filter chips that wrap, for the preview, the snapshot tests and the gallery: a row that fits, a run of
/// two rows, and a chip longer than the row.
struct WrapLayoutGallery: View {
    nonisolated static let muscles = ["All", "Chest", "Back", "Shoulders", "Legs", "Arms"]
    nonisolated static let equipment = [
        "All",
        "Barbell",
        "Dumbbell",
        "Cable",
        "Machine",
        "Bodyweight",
        "Kettlebell",
        "Band"
    ]
    nonisolated static let long = "An exercise whose name is longer than the row it stands in is given the row's width"

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            chips(["All", "Chest", "Back"])
            chips(Self.muscles + Self.equipment.dropFirst())
            chips(["Legs", Self.long, "Arms"])
        }
    }

    private func chips(_ titles: [String]) -> some View {
        WrapLayout {
            ForEach(Array(titles.enumerated()), id: \.offset) { place, title in
                PillButton(title, style: place == 0 ? .filled : .outline) {}
            }
        }
    }
}
