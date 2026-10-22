import LedgerDesign
import SwiftUI

/// ESTIMATED 1RM · 8 WEEKS, with the change in orange at its trailing edge, over eight columns: each week's
/// value over its 2 pt bar, and its label under it (v2). A week with no session keeps its label and draws no
/// bar. The current week's value and bar are orange (Pete's question 3, A). At accessibility sizes eight columns
/// do not fit, so the weeks are a list of week and value (N12). VoiceOver reads the bars as one chart, through
/// its descriptor (criterion 12); the list it reads row by row.
struct E1RMChart: View {
    let chart: ExerciseHistoryModel.Chart
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The tallest bar: three of the scale's largest steps, v2's 89 px rounded up.
    private static let track = 3 * LedgerSpacing.xxl

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.m) {
                Eyebrow(chart.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let delta = chart.delta {
                    Text(delta)
                        .ledgerFont(.caption)
                        .foregroundStyle(LedgerColor.accentText)
                }
            }
            if let empty = chart.empty {
                Text(empty)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
            } else if dynamicTypeSize.isAccessibilitySize {
                list
            } else {
                bars
            }
        }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: LedgerSpacing.s) {
            ForEach(chart.bars) { bar in
                VStack(spacing: LedgerSpacing.s) {
                    VStack(spacing: LedgerSpacing.s) {
                        if bar.number != nil {
                            Text(bar.value)
                                .ledgerFont(.caption)
                                .foregroundStyle(bar.isAccented ? LedgerColor.accentText : LedgerColor.inkMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Capsule()
                                .fill(bar.isAccented ? LedgerColor.accent : LedgerColor.inkFaint)
                                .frame(width: LedgerHairline.bar, height: Self.track * CGFloat(bar.level) / 100)
                        }
                    }
                    .frame(height: Self.track + 2 * LedgerSpacing.l, alignment: .bottom)
                    Text(bar.week)
                        .ledgerFont(.caption)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chart.spokenTitle)
        .accessibilityChartDescriptor(E1RMChartDescriptor(chart: chart))
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(chart.bars) { bar in
                HStack(spacing: LedgerSpacing.m) {
                    Text(bar.week)
                        .ledgerFont(.label)
                        .foregroundStyle(LedgerColor.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(bar.value)
                        .ledgerFont(.numeralS)
                        .foregroundStyle(bar.isAccented ? LedgerColor.accentText : LedgerColor.ink)
                }
                .padding(.vertical, LedgerSpacing.s)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
