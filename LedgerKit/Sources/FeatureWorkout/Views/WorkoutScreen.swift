import LedgerDesign
import SwiftUI

/// The workout's cover, drawn from a model: what previews draw. It only draws; `WorkoutRoot` holds the
/// store and its tasks.
///
/// A live workout is its pinned header over `ScrollView { WorkoutPage(model:) }` (standards §7: a screen
/// that scrolls is its pinned parts plus its page), and that is its one layout at every text size. The
/// VoiceOver trees and the references are taken from the header and the page stacked without the scroll
/// view (`WorkoutParts`, in the tests).
///
/// While the workout shows a rest, the rest panel floats over the page's end (F10 S6; v2). It is the
/// scroll view's bottom inset, so the page keeps as much room under its last row as the panel is tall, at
/// every text size: "+ Add set" and every row can be scrolled clear of it, and VoiceOver reaches it after
/// the page. Nothing is measured and no height is kept.
///
/// The panel is not of the screen's model, which a second of a rest does not change: the screen has a
/// slot for its bottom inset. `WorkoutRoot` fills it with the view that reads the store's panel, so that
/// view alone is drawn again each second; previews and tests hand the screen a panel's model.
struct WorkoutScreen<Inset: View>: View {
    let model: WorkoutScreenModel
    let send: (WorkoutAction) -> Void
    /// What floats over the page's end, or nothing: the rest panel, placed (`PlacedRestPanel`).
    let inset: Inset
    /// Where the page stands. It moves only to return to the top when the shown exercise changes; a change
    /// within an exercise leaves the page where the lifter scrolled it.
    @State private var position = ScrollPosition(edge: .top)

    init(model: WorkoutScreenModel, send: @escaping (WorkoutAction) -> Void, @ViewBuilder inset: () -> Inset) {
        self.model = model
        self.send = send
        self.inset = inset()
    }

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
                .safeAreaInset(edge: .bottom, spacing: 0) { inset }
                .onChange(of: workout.page.card?.exerciseIndex) {
                    // Another exercise is shown: its place and name are at the page's top (criterion 17).
                    position.scrollTo(edge: .top)
                }
            }
        case let .receipt(receipt):
            ReceiptScreen(model: receipt, send: send)
        case let .failed(failed):
            EmptyState(failed.title, body: failed.message, actionTitle: failed.close) { send(.minimize) }
                .padding(.horizontal, LedgerSpacing.screen)
        }
    }
}

extension WorkoutScreen where Inset == PlacedRestPanel? {
    /// The screen drawn from models alone, for previews and tests: with the rest panel `rest`, or none.
    init(model: WorkoutScreenModel, rest: RestPanelModel? = nil, send: @escaping (WorkoutAction) -> Void) {
        self.init(model: model, send: send) {
            rest.map { PlacedRestPanel(model: $0, send: send) }
        }
    }
}

/// The rest panel as the screen places it: inset from the cover's sides and from its end.
struct PlacedRestPanel: View {
    let model: RestPanelModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        RestPanel(model: model, send: send)
            .padding(.horizontal, LedgerSpacing.l)
            .padding(.bottom, LedgerSpacing.s)
    }
}
