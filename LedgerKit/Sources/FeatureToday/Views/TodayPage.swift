import LedgerDesign
import LedgerDomain
import SwiftUI

/// Everything Today scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees and the
/// snapshot references are taken from. Loaded, it is v2's column: the header, the week strip over a rule, the
/// day's card, the two tiles over a rule, and the recent workouts. While the first load runs it draws nothing,
/// so that a read of a few milliseconds does not flash a spinner; when the load failed it says so.
///
/// v2's gaps are 30 to 34 px between the parts and 26 to 30 px above a rule; they are `xxl` (32) and `xl` (24)
/// here, the scale's nearest steps.
struct TodayPage: View {
    let state: Loadable<TodayModel>
    let send: (TodayAction) -> Void

    var body: some View {
        content
            .padding(LedgerSpacing.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            EmptyView()
        case let .loaded(model):
            VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                TodayHeader(model: model.header, send: send)
                VStack(spacing: LedgerSpacing.xl) {
                    WeekStrip(days: model.weekStrip)
                    HairlineRule()
                }
                card(model.card)
                StatsRow(model: model.stats)
                RecentList(model: model.recent, send: send)
            }
        case .failed:
            EmptyState(TodayCopy.failedTitle, body: TodayCopy.failedBody)
        }
    }

    /// One card view per kind; "no program" and "block complete" are the same card with other words.
    @ViewBuilder
    private func card(_ card: TodayModel.Card) -> some View {
        switch card {
        case let .upNext(card): UpNextCard(model: card, send: send)
        case let .logged(card): LoggedCard(model: card, send: send)
        case let .restDay(card): RestDayCard(model: card, send: send)
        case let .noProgram(card), let .blockComplete(card): MessageCard(model: card, send: send)
        }
    }
}
