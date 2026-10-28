import LedgerDesign
import SwiftUI

/// The History list, drawn from its model and nothing else: a scroll view around `HistoryPage`, on the ground. The
/// whole screen scrolls, its title too, as the Library's does; it has no pinned part of its own (the tab bar is the
/// shell's). That is its one layout at every text size (the M1 convention for a screen that scrolls).
struct HistoryScreen: View {
    let model: HistoryModel
    let send: (HistoryRoute) -> Void

    var body: some View {
        ScrollView {
            HistoryPage(model: model, send: send)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LedgerColor.ground)
    }
}
