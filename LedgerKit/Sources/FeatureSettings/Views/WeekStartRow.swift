import LedgerDesign
import SwiftUI

/// "Week starts on" (N4): the chosen weekday as a menu of the seven, the system's, with the chosen one checked.
/// VoiceOver reads one button, "Week starts on, Monday", with the row's line as its hint. The menu's text is ink, as
/// every control of Settings is: the system's tint would be another colour on a screen with no accent.
struct WeekStartRow: View {
    let weekStart: SettingsModel.WeekStart
    let send: (SettingsAction) -> Void

    /// F15-S2-12: the row's title and line are drawn inside the menu's button, which speaks for them. Beside it, as
    /// texts no element held, the system's audit reported them "Potentially inaccessible" (found by hiding the rows
    /// one by one).
    var body: some View {
        SettingsRow {
            Menu {
                Picker(weekStart.title, selection: selection) {
                    ForEach(weekStart.days) { Text($0.title).tag($0.id) }
                }
            } label: {
                SettingsRowLayout {
                    SettingsRowLabel(title: weekStart.title, detail: weekStart.detail)
                } control: {
                    HStack(spacing: LedgerSpacing.xs) {
                        Text(weekStart.value)
                            .ledgerFont(.body)
                        LedgerIconView(.chevron, sizedAs: .label)
                            .rotationEffect(.degrees(90))
                    }
                    .foregroundStyle(LedgerColor.ink)
                    .ledgerHitTarget(alignment: .trailing)
                }
                // A menu's label centres the lines that wrap; the row's line starts at the leading edge.
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .tint(LedgerColor.ink)
            .accessibilityLabel(weekStart.title)
            .accessibilityValue(weekStart.value)
            .accessibilityHint(weekStart.detail)
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
