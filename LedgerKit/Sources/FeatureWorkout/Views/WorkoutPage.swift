import LedgerDesign
import SwiftUI

/// Everything of the workout that scrolls (F10 S5; standards §7: a screen that scrolls is its pinned parts
/// plus its page): the shown exercise's card, then "REMAINING". It holds no scroll view; `WorkoutScreen`
/// puts it in one under the pinned header, and the tests draw it without (`WorkoutParts`).
///
/// While a discard runs or the cover is closing no control of the page answers, as the header's do not.
struct WorkoutPage: View {
    let model: WorkoutPageModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
            if let card = model.card {
                ExerciseCard(model: card) { send(.edit($0)) }
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
