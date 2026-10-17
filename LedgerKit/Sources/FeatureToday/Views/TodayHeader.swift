import LedgerDesign
import SwiftUI

/// The top of Today (v2: the date in 400 12 px over the 600 32 px title, and a 40 px outlined circle at the
/// trailing edge): the date, the title and the Settings gear where v2 drew the "JD" avatar (product decision
/// #19). The title is the screen's heading, and the element the UI tests find (`today.title`).
///
/// v2's 10 px between the date and the title is `s` (8), the scale's nearest step. The gear is the 44 pt round
/// button, not a 40 px circle: a tap needs 44 points.
struct TodayHeader: View {
    let model: TodayModel.Header
    let send: (TodayAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: LedgerSpacing.m) {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.date)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted) // the prototype's .40 is below AA
                Text(model.title)
                    .ledgerFont(.title)
                    .foregroundStyle(LedgerColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("today.title")
                #if DEBUG
                    .onLongPressGesture { send(.titleLongPress) }
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The date and the title are read before the gear at every text size: by their places alone, a
            // title that large text pushes below the gear's top would be read after it.
            .accessibilitySortPriority(1)
            IconPillButton(model.settings.title, systemImage: "gearshape") { send(.route(model.settings.route)) }
        }
    }
}
