import LedgerDesign
import SwiftUI

/// Everything of the workout that scrolls (F10 S5; standards §7: a screen that scrolls is its pinned parts
/// plus its page): the shown exercise's card, or its superset's block (F10 S9), then "REMAINING". It holds
/// no scroll view; `WorkoutScreen` puts it in one under the pinned header, and the tests draw it without
/// (`WorkoutParts`).
///
/// While a discard runs or the cover is closing no control of the page answers, as the header's do not.
struct WorkoutPage: View {
    let model: WorkoutPageModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
            switch model.content {
            case let .card(card):
                ExerciseCard(model: card, send: send)
            case let .block(block):
                SupersetBlock(model: block, send: send)
            case nil:
                EmptyView()
            }
            if let remaining = model.remaining {
                RemainingList(model: remaining) { send(.edit($0)) }
            }
        }
        .padding(.horizontal, LedgerSpacing.screen)
        .padding(.top, LedgerSpacing.s)
        .padding(.bottom, LedgerSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!model.isEnabled)
    }
}
