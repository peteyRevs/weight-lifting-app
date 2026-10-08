import LedgerDesign
import SwiftUI

/// The workouts finished last (v2 "RECENT"): the eyebrow over F06's hairline rows, each one button with the
/// workout's name, its meta line and a chevron. With none yet, the model's sentence stands in their place.
///
/// At accessibility text sizes a row has no chevron: `HairlineRow` moves an accessory under the title there,
/// and a line that held the chevron alone would say nothing. The eyebrow then stands `m` above the first rule,
/// where v2's 4 px (`xs`) would leave the larger letters on it.
struct RecentList: View {
    let model: TodayModel.Recent
    let send: (TodayAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isLargeText = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: isLargeText ? LedgerSpacing.m : LedgerSpacing.xs) {
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
                            if !isLargeText {
                                LedgerIconView(.chevron, sizedAs: .body).foregroundStyle(LedgerColor.inkMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}
