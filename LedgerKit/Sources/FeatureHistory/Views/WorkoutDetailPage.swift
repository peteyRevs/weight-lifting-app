import LedgerDesign
import SwiftUI

/// Everything a past workout's detail scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees
/// and the snapshot references are taken from. Top to bottom: the day it started over its name, a heading; F10's
/// receipt (`ReceiptLayout`), whose rows each open their exercise's history; and "Delete workout". At accessibility
/// sizes the receipt stacks its tiles and targets itself (criterion 8).
struct WorkoutDetailPage: View {
    let model: WorkoutDetailModel
    let send: (HistoryRoute) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.date)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                // The element the UI tests find (`history.workout.title`).
                Text(model.title)
                    .ledgerFont(.title)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("history.workout.title")
            }
            ReceiptLayout(model: model.receipt) { place in
                if model.rowRoutes.indices.contains(place) {
                    send(model.rowRoutes[place])
                }
            }
            DeleteWorkoutButton(model: model.delete, onDelete: onDelete)
        }
        .padding(LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// N10's page: "This workout can't be read." over its line, then "Delete workout".
struct UnreadableWorkoutPage: View {
    let model: WorkoutDetailModel.Unreadable
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            EmptyState(model.title, body: model.body)
            DeleteWorkoutButton(model: model.delete, onDelete: onDelete)
        }
        .padding(LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Delete workout", text only and in ink: it deletes nothing by itself and asks first, in an alert drawn from the
/// model (F13 question 8, built to A): "Delete this workout?", what a delete removes, "Delete", the alert's one red,
/// and "Cancel", which sends nothing. Whether the alert is up is the button's own flag, as `DeleteDayButton`'s is.
struct DeleteWorkoutButton: View {
    let model: WorkoutDetailModel.Deletion
    let onDelete: () -> Void
    @State private var isConfirming = false

    var body: some View {
        PillButton(model.title, style: .ghost, flush: .leading) { isConfirming = true }
            .accessibilityIdentifier("history.workout.delete")
            .alert(model.question, isPresented: $isConfirming) {
                Button(model.confirm, role: .destructive, action: onDelete)
                Button(model.cancel, role: .cancel) {}
            } message: {
                Text(model.message)
            }
    }
}
