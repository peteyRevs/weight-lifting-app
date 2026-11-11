import LedgerDesign
import SwiftUI

/// Settings, drawn from its model and nothing else: a scroll view around `SettingsPage`, on the ground. The whole
/// screen scrolls, its title too; the navigation bar above it, with its back button, is the stack's. That is its
/// one layout at every text size (the M1 convention for a screen that scrolls). "Bar and plates"' sheet is up while
/// the model holds it, and keeps its last content while it goes down (`.sheet(item:)`, F14-S2 G3 S3); swiped away,
/// it is cancelled. "Delete all data"'s warning is the system's alert, and its sheet follows the plates' rules (S3).
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
        .alert(
            model.deleteWarningTitle,
            isPresented: warning,
            presenting: model.deleteWarning
        ) { warning in
            Button(warning.cancel.title, role: .cancel) { send(warning.cancel.action) }
            Button(warning.proceed.title, role: .destructive) { send(warning.proceed.action) }
        } message: { warning in
            Text(warning.message)
        }
        .sheet(item: deleteSheet) { delete in
            DeleteAllSheet(model: delete, send: send)
        }
    }

    /// Whether "Delete all data"'s warning is up. Only its buttons take it down, each sending its own action, so the
    /// system's dismissal changes nothing.
    private var warning: Binding<Bool> {
        Binding { model.deleteWarning != nil } set: { _ in }
    }

    /// "Delete all data"'s sheet; swiped away, it is cancelled.
    private var deleteSheet: Binding<DeleteAllSheetModel?> {
        Binding { model.deleteSheet } set: { shown in
            if shown == nil {
                send(.cancelDeleteAll)
            }
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
