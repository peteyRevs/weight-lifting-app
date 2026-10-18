#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// The previews of the "End workout?" sheet (F10 S7), one case each, drawn from the model the
    /// presentation makes of a `WorkoutPreview`'s workout. `PreviewTests` render every case and fail on a
    /// `#Preview` of the sheet that is not a case here; the references and the VoiceOver trees draw the
    /// same states.
    enum FinishSheetPreview: String, CaseIterable {
        case withSets = "End workout?"
        case zeroSets = "End workout, nothing logged"
        case kilograms = "End workout, in kilograms"
        case saving = "End workout, saving"

        /// The cover's state whose workout the sheet asks about.
        var workout: WorkoutPreview {
            switch self {
            case .withSets, .saving: .minutes
            case .zeroSets: .started
            case .kilograms: .dropSet
            }
        }

        /// The sheet's model; nil when the fixture does not build, which fails `PreviewTests`.
        var model: WorkoutFinishModel? {
            (try? workout.workout()).map {
                WorkoutPresentation.finishSheet($0, isSaving: self == .saving, locale: Fixtures.locale)
            }
        }

        @ViewBuilder var content: some View {
            if let model {
                FinishSheet(model: model) { _ in }
            }
        }
    }

    #Preview("End workout?") {
        FinishSheetPreview.withSets.content
    }

    #Preview("End workout, nothing logged") {
        FinishSheetPreview.zeroSets.content
    }

    #Preview("End workout, in kilograms") {
        FinishSheetPreview.kilograms.content
    }

    #Preview("End workout, saving") {
        FinishSheetPreview.saving.content
    }
#endif
