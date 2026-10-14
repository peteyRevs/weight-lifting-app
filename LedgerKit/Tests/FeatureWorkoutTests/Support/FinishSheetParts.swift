#if DEBUG
    @testable import FeatureWorkout
    import SwiftUI

    /// The "End workout?" sheet's pinned part, its title and "Keep lifting", over its page, without the
    /// scroll view the sheet puts the page in: what its VoiceOver trees and references are taken from
    /// (testing-strategy §2.6: a sheet whose content scrolls is a screen that scrolls).
    struct FinishSheetParts: View {
        let model: WorkoutFinishModel
        var send: (WorkoutAction) -> Void = { _ in }

        init(_ preview: FinishSheetPreview, send: @escaping (WorkoutAction) -> Void = { _ in }) throws {
            guard let built = preview.model else {
                throw WorkoutPreview.Unreadable()
            }
            self.init(model: built, send: send)
        }

        init(model: WorkoutFinishModel, send: @escaping (WorkoutAction) -> Void = { _ in }) {
            self.model = model
            self.send = send
        }

        var body: some View {
            FinishSheetFrame(model: model, send: send) {
                FinishSheetPage(model: model, send: send)
            }
        }
    }
#endif
