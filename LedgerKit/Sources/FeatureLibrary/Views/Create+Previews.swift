#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// The previews of the exercise sheet (F12 S3), one case each, drawn from the model the presentation makes of a
    /// fixed input. `PreviewTests` render every case; the snapshot and accessibility tests draw the same states.
    enum CreatePreview: String, CaseIterable {
        case empty = "New exercise"
        /// Criterion 9's exercise, under a name the catalog lacks (C13).
        case filled = "New exercise, filled in"
        /// Criterion 9: a name another exercise has.
        case nameTaken = "New exercise, name taken"
        /// N16: the save did not go through; the sheet stays up with the draft.
        case saveFailed = "New exercise, save failed"
        /// Criterion 10: the lifter's own exercise, opened from its history.
        case edit = "Edit exercise"

        func model() -> CreateExerciseModel {
            CreateExercisePresentation.make(CreatePreviewData.input(for: self))
        }

        var content: some View {
            CreateExerciseScreen(model: model(), send: { _ in }, onCancel: {})
        }
    }

    nonisolated enum CreatePreviewData {
        static let filled = CustomExerciseDraft(
            name: LibraryPreviewData.customName,
            equipment: .barbell,
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .triceps],
            pattern: .horizontalPush
        )

        static func input(for preview: CreatePreview) -> CreateExerciseInput {
            switch preview {
            case .empty:
                CreateExerciseInput(draft: CustomExerciseDraft(), locale: Fixtures.locale)
            case .filled:
                CreateExerciseInput(draft: filled, locale: Fixtures.locale)
            case .nameTaken:
                CreateExerciseInput(
                    draft: CustomExerciseDraft(name: "Barbell bench press"),
                    problem: .invalid(.duplicateName(ExerciseID(Fixtures.uuid(902)))),
                    locale: Fixtures.locale
                )
            case .saveFailed:
                CreateExerciseInput(draft: filled, problem: .failed, locale: Fixtures.locale)
            case .edit:
                CreateExerciseInput(draft: filled, isEdit: true, locale: Fixtures.locale)
            }
        }
    }

    #Preview("New exercise") {
        CreatePreview.empty.content
    }

    #Preview("New exercise, filled in") {
        CreatePreview.filled.content
    }

    #Preview("New exercise, name taken") {
        CreatePreview.nameTaken.content
    }

    #Preview("New exercise, save failed") {
        CreatePreview.saveFailed.content
    }

    #Preview("Edit exercise") {
        CreatePreview.edit.content
    }
#endif
