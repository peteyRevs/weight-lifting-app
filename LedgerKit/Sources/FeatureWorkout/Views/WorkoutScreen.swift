import LedgerDesign
import SwiftUI

/// The workout's cover, drawn from a model: what previews draw. It only draws; `WorkoutRoot` holds the
/// store and its tasks.
///
/// A live workout is its pinned header over `ScrollView { WorkoutPage(model:) }` (standards §7: a screen
/// that scrolls is its pinned parts plus its page), and that is its one layout at every text size. The
/// VoiceOver trees and the references are taken from the header and the page stacked without the scroll
/// view (`WorkoutParts`, in the tests).
struct WorkoutScreen: View {
    let model: WorkoutScreenModel
    let send: (WorkoutAction) -> Void
    /// Where the page stands. It moves only to return to the top when the shown exercise changes; a change
    /// within an exercise leaves the page where the lifter scrolled it.
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LedgerColor.ground)
    }

    @ViewBuilder private var content: some View {
        switch model {
        case .loading:
            EmptyView()
        case let .workout(workout):
            VStack(spacing: 0) {
                WorkoutHeader(model: workout.header, send: send)
                    .padding(.horizontal, LedgerSpacing.screen)
                    .padding(.vertical, LedgerSpacing.l)
                ScrollView {
                    WorkoutPage(model: workout.page, send: send)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollPosition($position)
                .onChange(of: workout.page.card?.exerciseIndex) {
                    // Another exercise is shown: its place and name are at the page's top (criterion 17).
                    position.scrollTo(edge: .top)
                }
            }
        case let .failed(failed):
            EmptyState(failed.title, body: failed.message, actionTitle: failed.close) { send(.minimize) }
                .padding(.horizontal, LedgerSpacing.screen)
        }
    }
}
