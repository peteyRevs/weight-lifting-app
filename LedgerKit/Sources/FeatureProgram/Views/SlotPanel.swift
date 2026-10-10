import LedgerDesign
import SwiftUI

/// The panel under the open exercise, inside its block and drawn from the row's panel alone. Top to bottom:
/// what needs the exercise to be stored (`SlotDetails`: the shown week's prescription, the steppers, the
/// progression, the drop set); the slot's actions as outlined pills that wrap, "Break out" and "Superset with
/// next" where the model carries them, then "Move up", "Move down" and "Remove"; and the loads of every week
/// (`WeekLoads`). A control the model does not carry is not drawn: an exercise that is not stored has the
/// actions alone, and the first of a day no "Move up". "Remove" is a pill like the others, not orange.
struct SlotPanel: View {
    let panel: SlotEditorModel
    let send: (DayEditorAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            if let details = panel.details {
                SlotDetails(details: details, send: send)
            }
            WrapLayout {
                // A superset action is identified by its place: there are two at most.
                ForEach(Array(panel.supersetActions.enumerated()), id: \.offset) { _, control in
                    ControlPill(control: control, send: send)
                }
                if let moveUp = panel.moveUp {
                    ControlPill(control: moveUp, send: send)
                }
                if let moveDown = panel.moveDown {
                    ControlPill(control: moveDown, send: send)
                }
                ControlPill(control: panel.remove, send: send)
            }
            if let details = panel.details {
                WeekLoads(strip: details.strip)
            }
        }
        .padding(.bottom, LedgerSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The load of every week of the block, "W1 185", "W2 190" … "W8 160 (deload)", as words that wrap: the
/// shown week's in ink, the others grey. No entry is orange, a deload week's and a held week's neither
/// (Pete's decision 1, A). Each entry is a whole string of the model and they are drawn one by one, never
/// joined here; VoiceOver reads the strip as one text, the model's own line.
struct WeekLoads: View {
    let strip: SlotEditorModel.WeekStrip

    var body: some View {
        WrapLayout(spacing: LedgerSpacing.m, lineSpacing: LedgerSpacing.xs) {
            // A week's place is its identity on screen.
            ForEach(Array(strip.entries.enumerated()), id: \.offset) { _, entry in
                Text(entry.text)
                    .ledgerFont(.caption)
                    .foregroundStyle(entry.isShown ? LedgerColor.ink : LedgerColor.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(strip.text)
    }
}
