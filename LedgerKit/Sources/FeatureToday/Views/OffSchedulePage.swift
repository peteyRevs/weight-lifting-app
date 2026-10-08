import LedgerDesign
import SwiftUI

/// Everything the off-schedule sheet scrolls, and never a scroll view: which week the days are from, then one
/// hairline row per day of the program, a button with the day's name, its exercises and estimate, and "Logged"
/// at its trailing edge on a day already done this week. Such a day can still be picked: the model gives every
/// row a route.
struct OffSchedulePage: View {
    let model: TodayModel.OffSchedule
    let onPick: (TodayRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            Text(model.subtitle)
                .ledgerFont(.bodyLight)
                .foregroundStyle(LedgerColor.inkMuted)
            HairlineList {
                // Days carry no identity of their own: they are drawn by their place.
                ForEach(Array(model.days.enumerated()), id: \.offset) { _, day in
                    HairlineRow(day.name, detail: day.detail) { onPick(day.route) } accessory: {
                        if let logged = day.logged {
                            Text(logged)
                                .ledgerFont(.caption)
                                .foregroundStyle(LedgerColor.inkMuted)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
