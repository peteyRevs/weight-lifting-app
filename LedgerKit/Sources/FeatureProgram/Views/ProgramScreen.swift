import LedgerDesign
import SwiftUI

/// The Program builder, drawn from its model and nothing else: a scroll view around `ProgramPage`, on the
/// ground. The whole screen scrolls, the program's name too; it has no pinned part of its own (the tab bar is
/// the shell's). That is its one layout at every text size (the M1 convention for a screen that scrolls).
///
/// The screen decides nothing and runs no task: every control sends the action its model carries, and the
/// store that answers them comes with S13. A drag on the page puts the keyboard of the name field away.
struct ProgramScreen: View {
    let model: ProgramBuilderModel
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        ScrollView {
            ProgramPage(model: model, send: send)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(LedgerColor.ground)
    }
}
