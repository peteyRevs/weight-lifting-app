import LedgerDesign
import SwiftUI

/// The Day editor, drawn from its model and nothing else: its header, pinned, over a scroll view around
/// `DayEditorPage`, on the ground. That is its one layout at every text size (the M1 convention for a screen
/// that scrolls).
///
/// The screen is given the editor's content only: when the program no longer holds the day there is nothing
/// to draw, and the store closes the screen. It decides nothing and runs no task: every control sends the
/// action its model carries, and the store that answers them comes with S14. A drag on the page puts the
/// keyboard of the name field away.
struct DayEditorScreen: View {
    let model: DayEditorModel.Content
    let send: (DayEditorAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DayEditorHeader(model: model, send: send)
            ScrollView {
                DayEditorPage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(LedgerColor.ground)
    }
}
