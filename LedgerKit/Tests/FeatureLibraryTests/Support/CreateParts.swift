#if DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import SwiftUI

    /// The exercise sheet's pinned parts and what it scrolls, without the scroll view: `SheetChrome`'s title and
    /// "Cancel" over the page and the foot, as `ExercisePickerParts` stands for F11's picker. What the sheet's
    /// VoiceOver trees, layout checks and references are taken from (testing-strategy §2.6).
    struct CreateParts: View {
        let model: CreateExerciseModel
        var send: (CreateExerciseAction) -> Void = { _ in }
        var onCancel: () -> Void = {}

        init(
            _ preview: CreatePreview,
            send: @escaping (CreateExerciseAction) -> Void = { _ in },
            onCancel: @escaping () -> Void = {}
        ) {
            model = preview.model()
            self.send = send
            self.onCancel = onCancel
        }

        var body: some View {
            SheetChrome(model.title, cancel: model.cancel, onCancel: onCancel) {
                CreateExercisePage(model: model, send: send)
                CreateExerciseFoot(model: model.foot, send: send)
            }
        }
    }
#endif
