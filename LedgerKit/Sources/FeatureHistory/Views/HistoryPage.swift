import LedgerDesign
import SwiftUI

/// Everything the History list scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees and the
/// snapshot references are taken from. Top to bottom: the title, then each week under its header, or the empty
/// state with its one button.
///
/// The spacing is the Library's: `xl` under the title and `xxl` between weeks, as on Today.
struct HistoryPage: View {
    let model: HistoryModel
    let send: (HistoryRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            // The element the UI tests find (`history.title`). Tab roots hide the navigation bar, so it is drawn here.
            Text(model.title)
                .ledgerFont(.title)
                .foregroundStyle(LedgerColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("history.title")
            switch model.content {
            case let .weeks(weeks):
                VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                    ForEach(weeks) { HistoryWeek(week: $0, send: send) }
                }
            case let .empty(empty):
                EmptyState(empty.title, body: empty.body, actionTitle: empty.actionTitle) { send(empty.route) }
            }
        }
        .padding(LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
