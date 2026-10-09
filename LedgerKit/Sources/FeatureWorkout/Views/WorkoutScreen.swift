import LedgerDesign
import SwiftUI

/// The workout's cover, drawn from a model: what previews, snapshots and the accessibility tests draw. It
/// only draws; `WorkoutRoot` holds the store and its tasks.
///
/// A live workout is its pinned header over the ground. S5 puts what scrolls under the header, as
/// `ScrollView { WorkoutPage(model:) }` (standards §7: a screen that scrolls is its pinned parts plus its
/// page).
struct WorkoutScreen: View {
    let model: WorkoutScreenModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        content
            .padding(.horizontal, LedgerSpacing.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LedgerColor.ground)
    }

    @ViewBuilder private var content: some View {
        switch model {
        case .loading:
            EmptyView()
        case let .workout(workout):
            WorkoutHeader(model: workout.header, send: send)
                .padding(.top, LedgerSpacing.l)
        case let .failed(failed):
            EmptyState(failed.title, body: failed.message, actionTitle: failed.close) { send(.minimize) }
        }
    }
}
