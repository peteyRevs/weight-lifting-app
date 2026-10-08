import LedgerDesign
import SwiftUI

/// Today's session, finished today. v2 draws no such state (v1 does, as a white card): it is set flat in v2's
/// type, as Up next is (Pete's decision 3): the eyebrow with the workout's length beside it, the day's name,
/// what was done, an outlined "View session", and where the block goes next. The eyebrow is grey, not v1's
/// orange: orange is the main button's, today's mark's, "UP NEXT"'s and the change's alone (decision #17).
struct LoggedCard: View {
    let model: TodayModel.Logged
    let send: (TodayAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            CardEyebrowLine(eyebrow: model.eyebrow, note: model.elapsed)
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.title)
                    .ledgerFont(.heading)
                    .foregroundStyle(LedgerColor.ink)
                Text(model.stats)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
            PillButton(model.action.title, flush: .leading) { send(.route(model.action.route)) }
            if let next = model.next {
                Text(next)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
        }
    }
}
