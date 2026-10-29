import LedgerDesign
import SwiftUI

/// "Week starts on" (N4): the chosen weekday as a menu of the seven, the system's, with the chosen one checked.
/// VoiceOver reads one button, "Week starts on, Monday", with the row's line as its hint. The menu's text is ink, as
/// every control of Settings is: the system's tint would be another colour on a screen with no accent.
struct WeekStartRow: View {
    let weekStart: SettingsModel.WeekStart
    let send: (SettingsAction) -> Void

    var body: some View {
        SettingsRow {
            SettingsRowLayout {
                SettingsRowLabel(title: weekStart.title, detail: weekStart.detail)
            } control: {
                Menu {
                    Picker(weekStart.title, selection: selection) {
                        ForEach(weekStart.days) { Text($0.title).tag($0.id) }
                    }
                } label: {
                    HStack(spacing: LedgerSpacing.xs) {
                        Text(weekStart.value)
                            .ledgerFont(.body)
                        LedgerIconView(.chevron, sizedAs: .label)
                            .rotationEffect(.degrees(90))
                    }
                    .foregroundStyle(LedgerColor.ink)
                    .ledgerHitTarget(alignment: .trailing)
                }
                .tint(LedgerColor.ink)
                .accessibilityLabel(weekStart.title)
                .accessibilityValue(weekStart.value)
                .accessibilityHint(weekStart.detail)
            }
        }
    }

    /// The chosen day's id; a choice sends that day's action.
    private var selection: Binding<Int> {
        Binding { weekStart.selected } set: { id in
            if let day = weekStart.days.first(where: { $0.id == id }) {
                send(day.action)
            }
        }
    }
}
