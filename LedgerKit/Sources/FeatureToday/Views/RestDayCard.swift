import LedgerDesign
import SwiftUI

/// A day with no session. v2 draws no such state (v1 does, as an ink card): it is set flat in v2's type
/// (Pete's decision 3): the eyebrow, "No session today", why, and two outlined pills, "Edit this week" and
/// "Train off-schedule" (decision #18), which asks the screen for the sheet. At accessibility text sizes the
/// pills stand one under the other.
struct RestDayCard: View {
    let model: TodayModel.RestDay
    let send: (TodayAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let buttons = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(spacing: LedgerSpacing.m))
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            Eyebrow(model.eyebrow)
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.title)
                    .ledgerFont(.heading)
                    .foregroundStyle(LedgerColor.ink)
                Text(model.body)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
            buttons {
                PillButton(model.editWeek.title, flush: .leading) { send(.route(model.editWeek.route)) }
                PillButton(model.offSchedule.title, flush: .leading) { send(.pickOffScheduleDay) }
            }
        }
    }
}
