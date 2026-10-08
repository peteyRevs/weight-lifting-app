import LedgerDesign
import LedgerDomain
import SwiftUI

/// Today, drawn from its state and nothing else (v2 `Today`): a scroll view around `TodayPage`, on the ground.
/// The whole screen scrolls, the header too, as in v2; it has no pinned part of its own (the tab bar is the
/// shell's). That is its one layout at every text size (the M1 convention for a screen that scrolls).
///
/// The screen decides nothing and runs no task. It answers the page's actions: a route goes to `onRoute`, and
/// "Train off-schedule" presents the sheet with the list the model's rest-day card holds. A model that stops
/// offering the list (a workout began, the day rolled over) takes the sheet away with it.
struct TodayScreen: View {
    let state: Loadable<TodayModel>
    let onRoute: (TodayRoute) -> Void
    var onTitleLongPress: () -> Void = {}
    @State private var isPickingDay = false

    var body: some View {
        ScrollView {
            TodayPage(state: state, send: handle)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LedgerColor.ground)
        .sheet(isPresented: $isPickingDay) {
            if let offSchedule {
                OffScheduleSheet(model: offSchedule, onPick: pick) { isPickingDay = false }
            }
        }
        .onChange(of: offSchedule == nil) { _, isGone in
            if isGone {
                isPickingDay = false
            }
        }
    }

    /// The list of the rest-day card, when that is the card on screen.
    private var offSchedule: TodayModel.OffSchedule? {
        guard case let .loaded(model) = state, case let .restDay(card) = model.card else {
            return nil
        }
        return card.offSchedule
    }

    private func handle(_ action: TodayAction) {
        switch action {
        case let .route(route): onRoute(route)
        case .pickOffScheduleDay: isPickingDay = true
        case .titleLongPress: onTitleLongPress()
        }
    }

    /// A day picked in the sheet: the sheet goes, and the day's route is the app's to resolve.
    private func pick(_ route: TodayRoute) {
        isPickingDay = false
        onRoute(route)
    }
}
