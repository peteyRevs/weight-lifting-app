#if DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import SwiftUI

    /// The receipt's pinned header over its page, without the scroll view the screen puts the page in, on
    /// the cover's ground: what the receipt's VoiceOver trees and references are taken from (testing-strategy
    /// §2.6). The header is inset as `ReceiptScreen` insets it.
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
                ReceiptHeader(model: model.header, send: send)
                    .padding(.horizontal, LedgerSpacing.screen)
                    .padding(.vertical, LedgerSpacing.l)
                ReceiptPage(model: model.page)
            }
            .background(LedgerColor.ground)
        }
    }
#endif
