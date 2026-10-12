import LedgerDesign
import SwiftUI

/// The Day editor's pinned bar, the one part of the screen that does not scroll: "Program", which goes back
/// to the builder, as plain text at the leading edge, and "Done" as an outlined pill at the trailing edge.
/// It is as high as its two buttons and their padding at every text size.
struct DayEditorBar: View {
    let model: DayEditorModel.Header
    let send: (DayEditorAction) -> Void

    var body: some View {
        HStack(spacing: LedgerSpacing.m) {
            PillButton(model.back.title, style: .ghost, flush: .leading) { send(model.back.action) }
            Spacer(minLength: 0)
            PillButton(model.done.title, flush: .trailing) { send(model.done.action) }
        }
        .padding(.horizontal, LedgerSpacing.screen)
        .padding(.vertical, LedgerSpacing.s)
    }
}
