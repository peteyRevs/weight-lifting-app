import LedgerDesign
import SwiftUI

/// "Bar and plates" (criterion 3, N12), drawn from its model and nothing else: the design system's sheet frame, with
/// "Cancel" at its title, the page between, and "Done", which saves, pinned at the foot. A sheet whose content
/// scrolls is a screen that scrolls (the M1 convention): `PlatesPage` is what scrolls, and its one layout at every
/// text size. It stands at full height, as the History's edit sheet does. Nothing on it wears the accent: Settings
/// has no primary action (C28).
struct PlateInventorySheet: View {
    let model: PlatesModel
    let send: (SettingsAction) -> Void

    var body: some View {
        SheetChrome(
            model.title,
            cancel: model.cancel,
            cancelIdentifier: "settings.plates.cancel",
            onCancel: cancel
        ) {
            ScrollView {
                PlatesPage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
            PlatesFoot(done: model.done, send: send)
        }
        .presentationDetents([.large])
    }

    private func cancel() {
        send(.cancelPlates)
    }
}

/// The sheet's pinned foot: a rule, then "Done", full width and ink, never the accent.
struct PlatesFoot: View {
    let done: SettingsModel.Link
    let send: (SettingsAction) -> Void

    var body: some View {
        VStack(spacing: LedgerSpacing.m) {
            HairlineRule()
            PillButton(done.title, fillsWidth: true) { send(done.action) }
                .accessibilityIdentifier("settings.plates.done")
        }
    }
}

/// What the plates sheet scrolls, and never a scroll view: the bar, stepped; the plate sizes, each a switch, in rows
/// that wrap; the line that says no plate is on, when none is; and "Reset to standard".
struct PlatesPage: View {
    let model: PlatesModel
    let send: (SettingsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            StepperField(
                model.bar.title,
                value: model.bar.value,
                spokenValue: model.bar.spokenValue,
                onDecrement: model.bar.decrement.map { action in { send(action) } },
                onIncrement: model.bar.increment.map { action in { send(action) } }
            )
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.platesTitle)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
                    .accessibilityAddTraits(.isHeader)
                FilterChipRow(
                    model.plates,
                    title: \.title,
                    spokenLabel: \.spokenLabel,
                    isSelected: \.isOn,
                    allowsMany: true
                ) { send($0.action) }
                if let empty = model.empty {
                    Text(empty)
                        .ledgerFont(.bodyLight)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
            }
            PillButton(model.reset.title, style: .ghost, flush: .leading) { send(model.reset.action) }
        }
        .padding(.vertical, LedgerSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
