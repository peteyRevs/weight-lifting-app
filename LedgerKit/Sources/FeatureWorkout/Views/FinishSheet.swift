import LedgerDesign
import SwiftUI

/// "End workout?" (F10 S7): the sheet "Finish" opens. A sheet whose content scrolls is a screen that
/// scrolls: its pinned part is `FinishSheetFrame` (the title and "Keep lifting"), and what scrolls is
/// `FinishSheetPage`. That is its one layout at every text size. `WorkoutRoot` presents it and the store
/// takes it away.
///
/// While a save runs nothing on it answers and it cannot be swiped away (`model.isEnabled`).
struct FinishSheet: View {
    let model: WorkoutFinishModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        FinishSheetFrame(model: model, send: send) {
            ScrollView {
                FinishSheetPage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .interactiveDismissDisabled(!model.isEnabled)
        .presentationDetents(WorkoutSheet.detents)
    }
}

/// The sheet's pinned part around its content: the title, a heading, and "Keep lifting" as the frame's
/// cancel, which VoiceOver's escape gesture also sends.
struct FinishSheetFrame<Content: View>: View {
    let model: WorkoutFinishModel
    let send: (WorkoutAction) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        SheetChrome(
            model.title,
            cancel: model.keepLifting,
            cancelIdentifier: "workout.finish.keep",
            onCancel: { send(.keepLifting) },
            content: { content }
        )
        .disabled(!model.isEnabled)
    }
}

/// What the sheet scrolls: what the workout holds so far, then its two ways to end. "Save workout" is the
/// sheet's one orange control; "Discard" is an outline of the same width, not a destructive colour
/// (product default O1), and one tap (O2). Once a save was asked for "Discard" is not drawn.
struct FinishSheetPage: View {
    let model: WorkoutFinishModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            Text(model.summary)
                .ledgerFont(.bodyLight)
                .foregroundStyle(LedgerColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: model.spokenSummary))
                .accessibilityIdentifier("workout.finish.summary")
            VStack(spacing: LedgerSpacing.s) {
                PrimaryButton(model.save) { send(.save) }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("workout.finish.save")
                if let discard = model.discard {
                    PillButton(discard, fillsWidth: true) { send(.discard) }
                        .accessibilityIdentifier("workout.finish.discard")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
