import LedgerDesign
import SwiftUI

/// Everything the builder scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees and
/// the snapshot references are taken from. Top to bottom: the program's name, the block with its weeks, the
/// selected week's schedule, and the training days every week shares.
///
/// The old design's cards are gone (Pete's decision 1, A): the parts stand flat on the ground, `xxl` apart
/// as Today's do, and the days are hairline rows.
struct ProgramPage: View {
    let model: ProgramBuilderModel
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
            ProgramHeader(model: model.header, send: send)
            BlockSection(model: model.block, notice: model.notice, send: send)
            WeekSection(model: model.week, send: send)
            TrainingDaysSection(model: model.days, send: send)
        }
        .padding(LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
