#if DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import SwiftUI

    /// The receipt's pinned header over its page, without the scroll view the screen puts the page in, on
    /// the cover's ground: what the receipt's VoiceOver trees and references are taken from (testing-strategy
    /// §2.6). The header is the screen's own pinned part (`ReceiptPinnedHeader`).
    struct ReceiptParts: View {
        let model: ReceiptScreenModel
        var send: (WorkoutAction) -> Void = { _ in }

        init(_ preview: ReceiptPreview, send: @escaping (WorkoutAction) -> Void = { _ in }) throws {
            guard let built = preview.model else {
                throw WorkoutPreview.Unreadable()
            }
            self.init(model: built, send: send)
        }

        init(model: ReceiptScreenModel, send: @escaping (WorkoutAction) -> Void = { _ in }) {
            self.model = model
            self.send = send
        }

        var body: some View {
            VStack(spacing: 0) {
                ReceiptPinnedHeader(model: model.header, send: send)
                ReceiptPage(model: model.page, rowActions: model.rowActions, send: send)
            }
            .background(LedgerColor.ground)
        }
    }
#endif
