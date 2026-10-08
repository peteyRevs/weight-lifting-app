import LedgerDesign
import SwiftUI

/// The card when there is no session to speak of: no program yet, or the block is complete. A title, which is
/// the card's heading, a sentence, and the screen's one orange button ("Set up program", "Open Program").
/// Neither v2 nor v1 draws these states; they are set in v2's type, as the other cards are (Pete's decision 3).
struct MessageCard: View {
    let model: TodayModel.Message
    let send: (TodayAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.title)
                    .ledgerFont(.heading)
                    .foregroundStyle(LedgerColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(model.body)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
            PrimaryButton(model.action.title) { send(.route(model.action.route)) }
        }
    }
}
