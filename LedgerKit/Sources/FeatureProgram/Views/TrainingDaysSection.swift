import LedgerDesign
import SwiftUI

/// The training days every week shares: "TRAINING DAYS" with the summary beside it, the helper line, one
/// hairline row per day, and "+ Add training day" as an outlined pill. A program with no day draws no list.
struct TrainingDaysSection: View {
    let model: ProgramBuilderModel.TrainingDays
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                SectionLine(eyebrow: model.title, note: model.summary)
                Text(model.helper)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
            if !model.cards.isEmpty {
                HairlineList {
                    ForEach(model.cards) { DayCard(model: $0, send: send) }
                }
            }
            ControlPill(control: model.addDay, send: send)
        }
    }
}
