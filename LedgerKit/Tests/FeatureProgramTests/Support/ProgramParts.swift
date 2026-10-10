#if DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import SwiftUI

    /// What a state of the preview registry scrolls and pins, stacked in reading order without the scroll view
    /// its screen puts the page in: what the VoiceOver trees and the snapshot references are taken from (the M1
    /// convention for a screen that scrolls, `docs/testing-strategy.md` §2.6).
    ///
    /// The builder has no pinned part, so its parts are its page alone, on the screen's ground. The exercise
    /// library's are `SheetChrome`'s title and "Cancel", the search field, the page, and the foot, as
    /// `ExercisePickerScreen` stacks them. A fixture that does not build draws nothing; `PreviewTests` fail on it.
    struct ProgramParts: View {
        let preview: ProgramPreview
        var sendBuilder: (ProgramBuilderAction) -> Void = { _ in }
        var sendLibrary: (ExercisePickerAction) -> Void = { _ in }

        var body: some View {
            // `try?`: the fixture's error is `PreviewTests`' to report.
            switch try? preview.subject() {
            case let .builder(model):
                ProgramPage(model: model, send: sendBuilder)
                    .background(LedgerColor.ground)
            case let .library(model):
                ExercisePickerParts(model: model, send: sendLibrary)
            case nil:
                EmptyView()
            }
        }
    }

    /// The exercise library sheet's pinned parts around its page, without the scroll view.
    struct ExercisePickerParts: View {
        let model: ExercisePickerModel
        var send: (ExercisePickerAction) -> Void = { _ in }

        var body: some View {
            SheetChrome(model.title, cancel: model.cancel.title, onCancel: cancel) {
                ExerciseSearchField(model: model.search, send: send)
                ExercisePickerPage(model: model, send: send)
                ExercisePickerFoot(model: model.foot, send: send)
            }
        }

        private func cancel() {
            send(model.cancel.action)
        }
    }

    extension ProgramPreview {
        /// The builder's states.
        nonisolated static let builders: [ProgramPreview] = [.builder, .deloadWeek, .emptyDay, .twoWeeks, .sixteenWeeks]
        /// The exercise library's states.
        nonisolated static let libraries: [ProgramPreview] = [.library, .libraryPicked, .libraryNothing]

        /// The builder's model of a builder state.
        func builderModel() throws -> ProgramBuilderModel {
            guard case let .builder(model) = try subject() else {
                throw NotThatScreen()
            }
            return model
        }

        /// The library's model of a library state.
        func libraryModel() throws -> ExercisePickerModel {
            guard case let .library(model) = try subject() else {
                throw NotThatScreen()
            }
            return model
        }

        struct NotThatScreen: Error {}
    }
#endif
