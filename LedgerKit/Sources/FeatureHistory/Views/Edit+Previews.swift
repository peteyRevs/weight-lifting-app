#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview of the edit sheet, one case each, drawn from the model its presentation makes of a fixed input, so
    /// a preview shows the words the app would. `PreviewTests` render every case and fail on a `#Preview` that is not a
    /// case here; the snapshot, accessibility and layout tests draw the same states' parts. None runs a task.
    enum EditPreview: String, CaseIterable {
        case unchanged = "Edit sets"
        /// A weight and a rep fixed: "Save" is on.
        case changed = "Edit sets, changed"
        /// A save that failed: its line stands over "Save".
        case failed = "Edit sets, save failed"
        /// Criterion 7: a pound workout read in kilograms (F13 question 5, built to A).
        case kilograms = "Edit sets in kilograms"

        func model() throws -> EditSetsModel {
            try EditSetsPresentation.make(EditPreviewData.input(for: self))
        }

        /// The sheet in this state. A fixture that does not build draws nothing, and fails `PreviewTests`.
        @ViewBuilder var content: some View {
            // `try?`: the fixture's own error is of no use to a preview.
            if let model = try? model() {
                EditSetsScreen(model: model, send: { _ in }, onCancel: {})
            }
        }
    }

    /// The fixed inputs of the previews: the previews' newest workout, its first set fixed where the state says so.
    nonisolated enum EditPreviewData {
        static func input(for preview: EditPreview) throws -> EditSetsInput {
            guard let workout = try Fixtures.history(weeks: 4).last,
                  let first = workout.exercises.first?.sets.first
            else {
                throw DetailPreviewData.NoHistory()
            }
            let units: Units = preview == .kilograms ? .kg : .lb
            var draft = workout
            if preview == .changed || preview == .failed {
                draft = SetEditing.stepping(first.id, .weight, .upward, in: draft, units: units)
                draft = SetEditing.stepping(first.id, .reps, .downward, in: draft, units: units)
            }
            return EditSetsInput(
                draft: draft,
                units: units,
                locale: Fixtures.locale,
                hasChanges: draft != workout,
                isSaving: false,
                saveFailed: preview == .failed,
                workoutGone: false
            )
        }
    }

    #Preview("Edit sets") {
        EditPreview.unchanged.content
    }

    #Preview("Edit sets, changed") {
        EditPreview.changed.content
    }

    #Preview("Edit sets, save failed") {
        EditPreview.failed.content
    }

    #Preview("Edit sets in kilograms") {
        EditPreview.kilograms.content
    }
#endif
