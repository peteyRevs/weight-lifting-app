import LedgerDesign
import SwiftUI

/// The cover's pinned header (v2 "Active workout"): "Minimize", the orange dot and the elapsed time, and
/// "Finish" in one row; under it the workout's name (v1's eyebrow; v2 draws none), one progress segment
/// per exercise and, while the watch is out of reach, the line that says so (F17 S8).
///
/// The elapsed time counts by the wall clock from the workout's start (`WorkoutTimeline`), so the model is
/// not rebuilt each second. VoiceOver reads its name and no time: a spoken time would be as old as the last
/// time the header was drawn. v2's 14 px time is `numeralS` (the spec's "Elapsed timer", 700 15 px,
/// tabular); its 18 px between the row and the bars is `l` (16).
///
/// **No word is ever broken (F15-S2-10).** "Minimize" and "Finish" are each drawn on one line at their own
/// width. Where the one row does not fit (the accessibility sizes), the time stands on its own line and the two
/// buttons in a row under it; where even they do not fit side by side, each stands on its own line
/// (`HeaderRowLayout`). The type never shrinks, nothing is truncated, and VoiceOver's order stays the row's.
struct WorkoutHeader: View {
    let model: WorkoutHeaderModel
    let send: (WorkoutAction) -> Void
    @Environment(\.workoutTimeline) private var timeline

    /// The prototype's 5 px dot.
    private static let dot: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            HeaderRowLayout(spacing: LedgerSpacing.s) {
                minimize
                elapsed
                finish
            }
            // VoiceOver reads "Minimize", the time, then "Finish" on one line or several, as in the one row.
            .accessibilityElement(children: .contain)
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Eyebrow(model.title)
                    .accessibilityIdentifier("workout.header.title")
                ProgressSegments(model.segments, label: model.progressLabel, value: model.progressValue)
                    .accessibilityIdentifier("workout.header.progress")
                if let connection = model.connection {
                    connectionLine(connection)
                }
            }
        }
    }

    /// "Minimize", on one line at its own width.
    private var minimize: some View {
        PillButton(model.minimize, style: .ghost, flush: .leading) { send(.minimize) }
            .disabled(!model.isEnabled)
            .accessibilityIdentifier("workout.header.minimize")
            .accessibilitySortPriority(2)
    }

    /// "Finish", on one line at its own width.
    private var finish: some View {
        PillButton(model.finish) { send(.finish) }
            .disabled(!model.isEnabled)
            .accessibilityIdentifier("workout.header.finish")
    }

    /// "Watch not connected — logging continues" (F17 criterion 12), under the bars: a text VoiceOver reads once
    /// where it stands, never as a frequently updating element. It wraps at the larger sizes, and nothing beside it
    /// is disabled.
    private func connectionLine(_ text: String) -> some View {
        Text(text)
            .ledgerFont(.caption)
            .foregroundStyle(LedgerColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("workout.header.connection")
    }

    private var elapsed: some View {
        HStack(spacing: LedgerSpacing.s) {
            Circle()
                .fill(LedgerColor.accentText)
                .frame(width: Self.dot, height: Self.dot)
            timeline.elapsed(since: model.startedAt)
                .ledgerFont(.numeralS)
                .foregroundStyle(LedgerColor.ink)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.elapsedLabel)
        // F15-S2-2: a text, as VoiceOver reads it. Without the trait the element is of no kind, and the system's
        // audit took it for a control 15 pt tall ("Hit area is too small").
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("workout.header.elapsed")
        .accessibilitySortPriority(1)
    }
}

/// The header's row (F15-S2-10): its three subviews, "Minimize", the time and "Finish", each at its own width, so no
/// word of theirs breaks. One row while the three fit, the time centred between the buttons as v2 draws it; else the
/// time on a line of its own over the two buttons, at either edge; else each on its own line, at the leading edge.
/// `spacing` stands between subviews side by side; lines touch, as the pills' own padding parts them (the room the
/// rest panel leaves the page, ruling 17, counts every point of the header).
/// One layout, not three views to choose from (`ViewThatFits`): the system's audit lost the elements of a header
/// that held three copies of them ("Dynamic Type partially unsupported" at the default size).
struct HeaderRowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(sizes, within: proposal.width ?? .infinity, spacing: spacing)
        let widths = rows.map { row in row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(row.count - 1) }
        let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
        return CGSize(width: proposal.width ?? widths.max() ?? 0, height: heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var top = bounds.minY
        for row in Self.rows(sizes, within: bounds.width, spacing: spacing) {
            let height = row.map { sizes[$0].height }.max() ?? 0
            for (place, index) in row.enumerated() {
                let size = sizes[index]
                let left: CGFloat = switch (row.count, place) {
                case (3, 1):
                    // Centred between the buttons' inner edges, as two equal spacers put it.
                    (bounds.minX + sizes[row[0]].width + bounds.maxX - sizes[row[2]].width - size.width) / 2
                case (_, 0): bounds.minX
                default: bounds.maxX - size.width
                }
                subviews[index].place(
                    at: CGPoint(x: left, y: top + (height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
            }
            top += height
        }
    }

    /// The subviews' indices by line: 0 "Minimize", 1 the time, 2 "Finish".
    static func rows(_ sizes: [CGSize], within width: CGFloat, spacing: CGFloat) -> [[Int]] {
        guard sizes.count == 3 else {
            return [Array(sizes.indices)]
        }
        if sizes.map(\.width).reduce(0, +) + 2 * spacing <= width {
            return [[0, 1, 2]]
        }
        if sizes[0].width + sizes[2].width + spacing <= width {
            return [[1], [0, 2]]
        }
        return [[1], [0], [2]]
    }
}
