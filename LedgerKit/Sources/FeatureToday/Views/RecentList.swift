import LedgerDesign
import SwiftUI

/// The workouts finished last (v2 "RECENT"): the eyebrow over F06's hairline rows, each one button with the
/// workout's name, its meta line and a chevron. With none yet, the model's sentence stands in their place.
struct RecentList: View {
    let model: TodayModel.Recent
    let send: (TodayAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Eyebrow(model.eyebrow)
            if let emptyMessage = model.emptyMessage {
                Text(emptyMessage)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
                    .padding(.top, LedgerSpacing.s)
            } else {
                HairlineList {
                    // Rows carry no identity of their own: they are drawn by their place.
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        HairlineRow(row.name, detail: row.meta) { send(.route(row.route)) } accessory: {
                            LedgerIconView(.chevron, sizedAs: .body).foregroundStyle(LedgerColor.inkMuted)
                        }
                    }
                }
            }
        }
    }
}
