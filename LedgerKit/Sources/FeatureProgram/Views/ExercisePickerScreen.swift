import LedgerDesign
import SwiftUI

/// The exercise library sheet, drawn from its model and nothing else. A sheet whose content scrolls is a
/// screen that scrolls (the M1 convention): pinned are `SheetChrome`'s title and "Cancel", the search field
/// under them and the "Add" button at the foot; what scrolls between them is `ExercisePickerPage`, the two
/// rows of chips and the exercises. That is its one layout at every text size.
///
/// The sheet decides nothing: every control sends the action its model carries, and the store that answers
/// them comes with S14. A drag on the list puts the keyboard away. The Day editor presents it with `.sheet`.
struct ExercisePickerScreen: View {
    let model: ExercisePickerModel
    let send: (ExercisePickerAction) -> Void

    var body: some View {
        SheetChrome(model.title, cancel: model.cancel.title, onCancel: cancel) {
            ExerciseSearchField(model: model.search, send: send)
            ScrollView {
                ExercisePickerPage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            ExercisePickerFoot(model: model.foot, send: send)
        }
    }

    /// "Cancel", and VoiceOver's escape gesture.
    private func cancel() {
        send(model.cancel.action)
    }
}

/// The search field, pinned under the sheet's title: an outlined pill, 44 pt high, that holds the model's
/// query and sends each change as typed. Its placeholder is its spoken label too. A tap anywhere on the pill
/// puts the cursor in the field, which by itself is only as high as its line of text.
struct ExerciseSearchField: View {
    let model: ExercisePickerModel.Search
    let send: (ExercisePickerAction) -> Void
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField(model.placeholder, text: Binding { model.query } set: { send(.setQuery($0)) })
            .ledgerFont(.body)
            .foregroundStyle(LedgerColor.ink)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isEditing)
            .padding(.horizontal, LedgerSpacing.l)
            .ledgerHitTarget(alignment: .leading)
            .onTapGesture { isEditing = true }
            .background {
                Capsule.ledgerPill.strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
            }
            .accessibilityLabel(model.placeholder)
    }
}

/// The sheet's foot, pinned under the list: a rule, and the orange button, the sheet's one use of the accent
/// (Pete's decision 1, A). With no exercise picked it reads "Select exercises to add" and is disabled.
struct ExercisePickerFoot: View {
    let model: ExercisePickerModel.Foot
    let send: (ExercisePickerAction) -> Void

    var body: some View {
        VStack(spacing: LedgerSpacing.m) {
            HairlineRule()
            PrimaryButton(model.title) {
                if let action = model.action {
                    send(action)
                }
            }
            .disabled(model.action == nil)
        }
    }
}
