import LedgerDesign
import SwiftUI

/// "Units" with "LB" and "KG" (N5): the design system's two-option control, which VoiceOver reads as the group
/// "Units", each option by its spoken name ("pounds"), the chosen one selected, the row's line as its hint.
struct UnitsRow: View {
    let units: SettingsModel.Units
    let send: (SettingsAction) -> Void

    var body: some View {
        SettingsRow {
            SettingsRowLayout {
                SettingsRowLabel(title: units.title, detail: units.detail)
            } control: {
                SegmentedChoice(
                    units.title,
                    hint: units.detail,
                    options: units.options,
                    title: \.title,
                    spokenLabel: \.spokenLabel,
                    isSelected: \.isSelected
                ) { send($0.action) }
            }
        }
    }
}

/// "Default rest", stepped by 15 s within 30–300 s (criterion 2): the design system's stepper, one adjustable
/// element to VoiceOver ("Default rest, 1 minute, 30 seconds"), with the row's line as its hint and under it. A step
/// past a bound is switched off.
struct RestRow: View {
    let rest: SettingsModel.Rest
    let send: (SettingsAction) -> Void

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                StepperField(
                    rest.title,
                    value: rest.value,
                    spokenValue: rest.spokenValue,
                    onDecrement: rest.decrement.map { action in { send(action) } },
                    onIncrement: rest.increment.map { action in { send(action) } }
                )
                .accessibilityHint(rest.detail)
                Text(rest.detail)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A preference that is on or off: its title over its line, with the design system's switch, which is ink and never
/// orange. A tap anywhere on the row sends the model's action; the switch shows the model's state and keeps none.
/// VoiceOver reads it as a switch, its title, on or off, with the line as its hint (criterion 8).
struct SwitchRow: View {
    let model: SettingsModel.Switch
    let send: (SettingsAction) -> Void

    var body: some View {
        SettingsRow {
            Toggle(isOn: Binding { model.isOn } set: { _ in send(model.action) }) {
                VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                    Text(model.title)
                        .ledgerFont(.body)
                        .foregroundStyle(LedgerColor.ink)
                    Text(model.detail)
                        .ledgerFont(.label)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
                .multilineTextAlignment(.leading)
            }
            .toggleStyle(.ledger)
            .accessibilityLabel(model.title)
            .accessibilityHint(model.detail)
        }
    }
}
