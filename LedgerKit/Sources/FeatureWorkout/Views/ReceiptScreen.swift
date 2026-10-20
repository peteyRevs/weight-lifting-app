import LedgerDesign
import SwiftUI

/// The receipt of the workout this cover saved (F10 S7b): its pinned header over
/// `ScrollView { ReceiptPage(model:) }`, its one layout at every text size (standards §7). The VoiceOver
/// trees and the references are taken from the header and the page stacked without the scroll view
/// (`ReceiptParts`, in the tests). Nothing of the live workout is drawn: no rest panel, no timer.
///
/// VoiceOver's escape gesture is "Done", as the sheet's is "Keep lifting".
struct ReceiptScreen: View {
    let model: ReceiptScreenModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ReceiptPinnedHeader(model: model.header, send: send)
            ScrollView {
                ReceiptPage(model: model.page)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityAction(.escape) { send(.done) }
    }
}

/// The receipt's pinned part: its header, inset as the cover's header is. `ReceiptScreen` and the tests'
/// `ReceiptParts` both draw this one view.
struct ReceiptPinnedHeader: View {
    let model: ReceiptHeaderModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        ReceiptHeader(model: model, send: send)
            .padding(.horizontal, LedgerSpacing.screen)
            .padding(.vertical, LedgerSpacing.l)
    }
}

/// What the receipt scrolls: `LedgerDesign`'s `ReceiptLayout`, inset as the cover's page is.
struct ReceiptPage: View {
    let model: ReceiptLayout.Model

    var body: some View {
        ReceiptLayout(model: model)
            .padding(.horizontal, LedgerSpacing.screen)
            .padding(.bottom, LedgerSpacing.xl)
    }
}
