import LedgerDesign
import SwiftUI

/// The part of the open exercise's panel that needs the exercise to be stored: the shown week's prescription,
/// one stepper per field, "PROGRESSION" with its chips and what the chosen one does, and the drop set's
/// switch.
struct SlotDetails: View {
    let details: SlotEditorModel.Details
    let send: (DayEditorAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            WeekPrescription(week: details.week)
            VStack(spacing: LedgerSpacing.m) {
                ForEach(details.fields) { SlotStepper(field: $0, send: send) }
            }
            ProgressionChips(model: details.progression, send: send)
            DropSetSwitch(model: details.dropSet, send: send)
        }
    }
}

/// The shown week's prescription: "WEEK 3" over "5 × 5 @ 185 lb · RPE 8".
///
/// The eyebrow is the Day editor's one use of the accent (Pete's decision 1, A): it is orange when the shown
/// week is a deload week or holds its load after a missed week, and grey otherwise. The model's two flags
/// pick the colour; the eyebrow is one string of the model and is tinted whole, never split here. VoiceOver
/// reads the two lines as one text, the eyebrow with the prescription as its value, and not as a heading.
struct WeekPrescription: View {
    let week: SlotEditorModel.WeekLine

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Eyebrow(week.eyebrow, tint: week.isDeload || week.isHeld ? .accent : .muted)
            Text(week.line)
                .ledgerFont(.numeralS)
                .foregroundStyle(LedgerColor.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(week.eyebrow)
        .accessibilityValue(week.line)
    }
}

/// One field of the slot as the design system's stepper, drawn with the field's spoken label and its value
/// ("Sets" over "5": Pete's decision 1, A, has the six field labels in the small grey label style, not in
/// capitals). To VoiceOver it is one adjustable element, "Sets, 5", whose swipes send the field's two
/// actions. Both steps are always offered: at a field's limit the Domain holds the value.
struct SlotStepper: View {
    let field: SlotEditorModel.Field
    let send: (DayEditorAction) -> Void

    var body: some View {
        StepperField(
            field.spokenLabel,
            value: field.value,
            onDecrement: { send(field.decrement) },
            onIncrement: { send(field.increment) }
        )
    }
}

/// "Drop set" over its note, with the design system's switch, which is ink and never orange. A tap anywhere
/// on the row sends the model's action, which turns the drop set to its other state; the switch shows the
/// model's state and keeps none. VoiceOver reads it as a switch, "Drop set", on or off, with the note as its
/// hint.
struct DropSetSwitch: View {
    let model: SlotEditorModel.DropSet
    let send: (DayEditorAction) -> Void

    var body: some View {
        Toggle(isOn: Binding { model.isOn } set: { _ in send(model.action) }) {
            VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                Text(model.title)
                    .ledgerFont(.body)
                    .foregroundStyle(LedgerColor.ink)
                Text(model.note)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
            .multilineTextAlignment(.leading)
        }
        .toggleStyle(.ledger)
        .accessibilityLabel(model.title)
        .accessibilityHint(model.note)
    }
}
