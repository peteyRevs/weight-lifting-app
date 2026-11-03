import LedgerDesign
import SwiftUI

/// The edit sheet, drawn from its model and nothing else (F13 S3). A sheet whose content scrolls is a screen that
/// scrolls (the M1 convention): pinned are `SheetChrome`'s title and "Cancel" and, at the foot, "Save"; what scrolls
/// between them is `EditSetsPage`. That is its one layout at every text size. It stands at full height, as
/// `FinishSheet` does: at half height the system draws a sheet inset, which takes a 44 pt target under 44 pt.
struct EditSetsScreen: View {
    let model: EditSetsModel
    let send: (EditSetsAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetChrome(model.title, cancel: model.cancel, cancelIdentifier: "history.edit.cancel", onCancel: onCancel) {
            ScrollView {
                EditSetsPage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
            EditSetsFoot(model: model.foot, send: send)
        }
        .disabled(!model.isEnabled)
        .presentationDetents([.large])
    }
}

/// The pinned foot: a failed save's line, then "Save", the sheet's one orange (N6), off until something changed.
struct EditSetsFoot: View {
    let model: EditSetsModel.Foot
    let send: (EditSetsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            HairlineRule()
            if let problem = model.problem {
                Text(problem)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(model.save) {
                if let action = model.action {
                    send(action)
                }
            }
            .disabled(model.action == nil)
            .accessibilityIdentifier("history.edit.save")
        }
    }
}
