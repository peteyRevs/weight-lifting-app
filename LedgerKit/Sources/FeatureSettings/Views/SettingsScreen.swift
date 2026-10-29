import LedgerDesign
import SwiftUI

/// Settings, drawn from its model and nothing else: a scroll view around `SettingsPage`, on the ground. The whole
/// screen scrolls, its title too; the navigation bar above it, with its back button, is the stack's. That is its
/// one layout at every text size (the M1 convention for a screen that scrolls).
struct SettingsScreen: View {
    let model: SettingsModel
    let send: (SettingsAction) -> Void

    var body: some View {
        ScrollView {
            SettingsPage(model: model, send: send)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LedgerColor.ground)
    }
}
