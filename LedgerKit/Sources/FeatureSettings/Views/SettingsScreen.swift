import LedgerDesign
import SwiftUI

/// Settings, drawn from its model and nothing else: a scroll view around `SettingsPage`, on the ground. The whole
/// screen scrolls, its title too; the navigation bar above it, with its back button, is the stack's. That is its
/// one layout at every text size (the M1 convention for a screen that scrolls). "Bar and plates"' sheet is up while
/// the model holds it, and keeps its last content while it goes down (`.sheet(item:)`, F14-S2 G3 S3); swiped away,
/// it is cancelled.
struct SettingsScreen: View {
    let model: SettingsModel
    let send: (SettingsAction) -> Void

    var body: some View {
        ScrollView {
            SettingsPage(model: model, send: send)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LedgerColor.ground)
        .sheet(item: sheet) { plates in
            PlateInventorySheet(model: plates, send: send)
        }
    }

    /// The model's plates sheet; a sheet swiped away is cancelled.
    private var sheet: Binding<PlatesModel?> {
        Binding { model.platesSheet } set: { shown in
            if shown == nil {
                send(.cancelPlates)
            }
        }
    }
}
