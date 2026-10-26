import LedgerDesign
import SwiftUI

/// An exercise's history, drawn from its model: a scroll view around `ExerciseHistoryPage`, on the ground, under
/// the pushed screen's navigation bar, its back button and, for the lifter's own exercise, "Edit".
struct ExerciseHistoryScreen: View {
    let model: ExerciseHistoryModel
    let send: (LibraryRoute) -> Void
    /// "Edit" (F12 S3): drawn in the bar when the model has it.
    var onEdit: () -> Void = {}

    var body: some View {
        ScrollView {
            ExerciseHistoryPage(model: model, send: send)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LedgerColor.ground)
        .toolbar {
            if let edit = model.edit {
                ToolbarItem(placement: .primaryAction) {
                    Button(edit, action: onEdit)
                        .accessibilityIdentifier("library.history.edit")
                }
            }
        }
    }
}

/// Everything the history scrolls, and never a scroll view (the M1 convention): the equipment and muscle over
/// the name, the three stats, a rule, the chart, then the session log (v2). The stats stack at accessibility
/// sizes (`StatTileRow`), and the chart becomes a list (`E1RMChart`).
struct ExerciseHistoryPage: View {
    let model: ExerciseHistoryModel
    let send: (LibraryRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.eyebrow)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted)
                Text(model.title)
                    .ledgerFont(.title)
                    .foregroundStyle(LedgerColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("library.history.title")
            }
            VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
                StatTileRow {
                    ForEach(model.stats) { stat in
                        StatTile(
                            value: stat.value,
                            unit: stat.unit,
                            caption: stat.caption,
                            accessibilitySummary: stat.spoken,
                            isValueAccented: stat.isAccented
                        )
                    }
                }
                HairlineRule()
            }
            E1RMChart(chart: model.chart)
            SessionLog(log: model.log, send: send)
        }
        .padding(LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
