import LedgerDesign
import SwiftUI

/// The Library, drawn from its model and nothing else: a scroll view around `LibraryPage`, on the ground. The
/// whole screen scrolls, its title and search field too, as the prototype's does; it has no pinned part of its
/// own (the tab bar is the shell's). That is its one layout at every text size (the M1 convention for a screen
/// that scrolls). A drag on the page puts the keyboard away.
struct LibraryScreen: View {
    let model: LibraryModel
    let send: (LibraryAction) -> Void

    var body: some View {
        ScrollView {
            LibraryPage(model: model, send: send)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(LedgerColor.ground)
    }
}
