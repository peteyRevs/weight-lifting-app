import LedgerDesign
import SwiftUI

/// Today's session, not yet logged, or the workout that is running (v2 "UP NEXT"): the orange eyebrow with the
/// week and the estimate, the day's name, one hairline row per exercise with its scheme, and the screen's one
/// orange button. For a live workout the button counts the time since the workout started, by the wall clock.
///
/// v2's 25 px title is `heading` (27), its nearest role; its 20 px gaps are `l` (16), and the 26 px above the
/// button is `xl` (24). The rows are F06's `HairlineRow` as its gallery draws this very line.
struct UpNextCard: View {
    let model: TodayModel.UpNext
    let send: (TodayAction) -> Void
    @Environment(\.todayTimerPause) private var timerPause

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            CardEyebrowLine(eyebrow: model.eyebrow, tint: .accent, note: model.meta)
            Text(model.title)
                .ledgerFont(.heading)
                .foregroundStyle(LedgerColor.ink)
            HairlineList {
                // Rows carry no identity and two can be equal: they are drawn by their place.
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    HairlineRow(row.name) {
                        Text(row.scheme)
                            .ledgerFont(.numeralS)
                            .foregroundStyle(LedgerColor.inkSecondary)
                    }
                }
            }
            button.padding(.top, LedgerSpacing.s)
        }
    }

    @ViewBuilder private var button: some View {
        switch model.action {
        case let .start(action):
            PrimaryButton(action.title, icon: .arrow) { send(.route(action.route)) }
        case let .resume(action, startedAt):
            PrimaryButton(
                label: TodayCopy.resume(since: startedAt, pausedAt: timerPause),
                accessibilityLabel: action.title,
                icon: .arrow
            ) { send(.route(action.route)) }
        }
    }
}
