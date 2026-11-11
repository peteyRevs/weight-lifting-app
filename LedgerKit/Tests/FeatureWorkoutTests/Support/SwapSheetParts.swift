#if DEBUG
    @testable import FeatureWorkout
    import SwiftUI

    /// The swap sheet's pinned part, its title and "Cancel", over its page, without the scroll view the sheet
    /// puts the page in: what its VoiceOver trees and references are taken from (testing-strategy §2.6: a
    /// sheet whose content scrolls is a screen that scrolls).
    struct SwapSheetParts: View {
        let model: SwapSheetModel
        var send: (WorkoutAction) -> Void = { _ in }

        init(_ preview: SwapSheetPreview, send: @escaping (WorkoutAction) -> Void = { _ in }) throws {
            guard let built = preview.model else {
                throw WorkoutPreview.Unreadable()
            }
            self.init(model: built, send: send)
        }

        init(model: SwapSheetModel, send: @escaping (WorkoutAction) -> Void = { _ in }) {
            self.model = model
            self.send = send
        }

        var body: some View {
            SwapSheetFrame(model: model, send: send) {
                SwapSheetPage(model: model, send: send)
            }
        }
    }
#endif
