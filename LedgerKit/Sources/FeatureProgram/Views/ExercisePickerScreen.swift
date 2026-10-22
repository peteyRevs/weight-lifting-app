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

/// The search field, pinned under the sheet's title: `LedgerDesign`'s `SearchField` (moved there for F12's
/// Library), holding the model's query and sending each change as typed. Its placeholder is its spoken label too.
struct ExerciseSearchField: View {
    let model: ExercisePickerModel.Search
    let send: (ExercisePickerAction) -> Void

    var body: some View {
        SearchField(model.placeholder, short: model.shortPlaceholder, text: model.query) { send(.setQuery($0)) }
    }
}

/// The sheet's foot, pinned under the list: a rule (the one that closes the list, which draws none of its
/// own here), and the orange button, the sheet's one use of the accent
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
