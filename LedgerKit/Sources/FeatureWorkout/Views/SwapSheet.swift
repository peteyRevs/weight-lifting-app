import LedgerDesign
import SwiftUI

/// "Swap exercise" (F10 S8b; v2 "Active workout", the swap sheet): the sheet the card's swap button opens. A
/// sheet whose content scrolls is a screen that scrolls: its pinned part is `SwapSheetFrame` (the title and
/// "Cancel"), and what scrolls is `SwapSheetPage`. That is its one layout at every text size. `WorkoutRoot`
/// presents it and the store takes it away.
struct SwapSheet: View {
    let model: SwapSheetModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        SwapSheetFrame(model: model, send: send) {
            ScrollView {
                SwapSheetPage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Full height, as "End workout?" stands, for the same reason: at half height the system draws the
        // sheet smaller, which takes the frame's 44 pt cancel under 44 pt.
        .presentationDetents(FinishSheet.detents)
    }
}

/// The sheet's pinned part around its content: the title, a heading, and "Cancel" as the frame's cancel,
/// which VoiceOver's escape gesture also sends.
struct SwapSheetFrame<Content: View>: View {
    let model: SwapSheetModel
    let send: (WorkoutAction) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        SheetChrome(
            model.title,
            cancel: model.cancel,
            cancelIdentifier: "workout.swap.cancel",
            onCancel: { send(.cancelSwap) },
            content: { content }
        )
    }
}

/// What the sheet scrolls: the line, what became of the read when it offers nothing, "Also update program",
/// then one row per alternative. Each row is one button, read as its name, its equipment and load, and
/// "Use"; "Use" is the sheet's orange, on every row as v2 draws it (S8 ruling Q8). The switch is the design
/// system's, in ink.
struct SwapSheetPage: View {
    let model: SwapSheetModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            Text(model.line)
                .ledgerFont(.bodyLight)
                .foregroundStyle(LedgerColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.message {
                Text(message)
                    .ledgerFont(.body)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("workout.swap.message")
            }
            if let toggle = model.toggle {
                Toggle(isOn: Binding { toggle.isOn } set: { send(.updateProgram($0)) }) {
                    Text(toggle.label)
                        .ledgerFont(.body)
                        .foregroundStyle(LedgerColor.ink)
                }
                .toggleStyle(.ledger)
                .accessibilityIdentifier("workout.swap.updateProgram")
            }
            if !model.rows.isEmpty {
                rows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        HairlineList {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                HairlineRow(row.name, detail: row.detail, action: { send(.edit(row.choose)) }, accessory: {
                    Text(row.use)
                        .ledgerFont(.caption)
                        .foregroundStyle(LedgerColor.accentText)
                })
                .accessibilityIdentifier("workout.swap.row.\(index)")
            }
        }
    }
}
