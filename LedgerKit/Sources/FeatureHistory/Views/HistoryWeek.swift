import LedgerDesign
import SwiftUI

/// One week of the list: its header, a heading, then its workouts as F06's hairline rows, each under its own rule,
/// and a rule that closes the week (as the Library's sections).
struct HistoryWeek: View {
    let week: HistoryModel.Week
    let send: (HistoryRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(week.title)
            VStack(spacing: 0) {
                ForEach(week.rows) { HistoryRow(row: $0, send: send) }
                HairlineRule()
            }
        }
    }
}

/// One workout, F06's hairline row as one button, as Today's RECENT draws one: its name, the meta line under it, and
/// its records' badge at the trailing edge, bold and in ink (F13 question 6, built to A: never orange, N6). A tap
/// opens its detail. Neither text has a line limit, so at accessibility sizes the name wraps and is never truncated
/// (criterion 8), and the badge moves under it. VoiceOver reads the name with the spoken meta and badge as its value
/// ("Wednesday, 58 minutes, 24,180 pounds, 1 PR").
struct HistoryRow: View {
    let row: HistoryModel.Row
    let send: (HistoryRoute) -> Void

    var body: some View {
        HairlineRow(row.name, detail: row.meta) { send(row.route) } accessory: {
            if let badge = row.badge {
                Text(badge)
                    .ledgerFont(.numeralS)
                    .foregroundStyle(LedgerColor.ink)
            }
        }
        .accessibilityLabel(row.name)
        .accessibilityValue(row.spokenValue)
    }
}
