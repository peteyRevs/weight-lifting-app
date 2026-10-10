import LedgerDesign
import SwiftUI

/// Everything the Day editor scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees
/// and the snapshot references are taken from, under the pinned bar. Top to bottom: the header, with the
/// day's name; the day's exercises, one block per superset or per exercise on its own, `l` apart; "+ Add
/// exercise from library" as an outlined pill; and "Delete day". A day with no exercise draws the header
/// and the two buttons alone.
struct DayEditorPage: View {
    let model: DayEditorModel.Content
    let send: (DayEditorAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            // The header pads itself, as the builder's page pads its own.
            DayEditorHeader(model: model, send: send)
            VStack(alignment: .leading, spacing: LedgerSpacing.l) {
                ForEach(model.groups) { ExerciseGroup(group: $0, send: send) }
                VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                    ControlPill(control: model.addExercise, send: send)
                    DeleteDayButton(model: model.deleteDay, send: send)
                }
            }
            .padding(.horizontal, LedgerSpacing.screen)
        }
        .padding(.top, LedgerSpacing.xs)
        .padding(.bottom, LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Delete day", text only: it deletes nothing by itself and asks first, in an alert drawn from the model's
/// confirmation: "Delete Lower B?", the line that says in how many weeks the day is scheduled (none for a
/// day no week schedules), "Delete" and "Cancel". "Delete" sends the model's action; "Cancel" sends nothing.
/// Whether the alert is showing is the button's own flag.
struct DeleteDayButton: View {
    let model: DayEditorModel.DeleteDay
    let send: (DayEditorAction) -> Void
    @State private var isConfirming = false

    var body: some View {
        let confirmation = model.confirmation
        PillButton(model.title, style: .ghost, flush: .leading) { isConfirming = true }
            .alert(confirmation.title, isPresented: $isConfirming) {
                Button(confirmation.confirm.title, role: .destructive) { send(confirmation.confirm.action) }
                Button(confirmation.cancel, role: .cancel) {}
            } message: {
                if let message = confirmation.message {
                    Text(message)
                }
            }
    }
}
