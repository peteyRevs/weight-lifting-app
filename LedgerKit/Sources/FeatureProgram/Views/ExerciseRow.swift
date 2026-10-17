import LedgerDesign
import SwiftUI

/// One exercise of the day, a row under its rule and one button that opens its panel, or closes it, with the
/// panel under it while the model says it is open: the exercise's place ("1", or "4A" in a superset) before
/// its name, under them the line "Barbell · +5/wk · RPE 8 · 2:30 rest", at the trailing edge the shown week's
/// scheme over its load (no load for an exercise that is not stored), and a caret that points down on a
/// closed row and up on the open one. Nothing on the row is orange, open or closed (Pete's decision 1, A).
///
/// The row and its panel are a disclosure group, so that VoiceOver says "expanded" or "collapsed" in its own
/// words: it reads the row as "4A, Lat Pulldown" with the scheme, the load and the line as its value. The
/// group keeps no state: it shows the model's `isOpen`, and a tap sends the row's action. At accessibility
/// text sizes the scheme and the load stand under the texts.
struct ExerciseRow: View {
    let row: DayEditorModel.Row
    let send: (DayEditorAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        DisclosureGroup(isExpanded: Binding { row.isOpen } set: { _ in send(row.action) }) {
            if let panel = row.panel {
                SlotPanel(panel: panel, send: send)
            }
        } label: {
            content
        }
        .disclosureGroupStyle(ExerciseDisclosure(spokenLabel: row.spokenLabel, spokenValue: row.spokenValue))
    }

    private var content: some View {
        let isLargeText = dynamicTypeSize.isAccessibilitySize
        let layout = isLargeText
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LedgerSpacing.m))
        return HStack(spacing: LedgerSpacing.m) {
            layout {
                texts
                prescription(isLargeText: isLargeText)
            }
            // The chevron of the design system, turned: down to open, up to close.
            LedgerIconView(.chevron, sizedAs: .body)
                .foregroundStyle(LedgerColor.inkMuted)
                .rotationEffect(.degrees(row.isOpen ? -90 : 90))
        }
        .padding(.vertical, LedgerSpacing.l)
        .contentShape(Rectangle())
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.s) {
                Text(row.index)
                    .ledgerFont(.numeralS)
                    .foregroundStyle(LedgerColor.inkMuted)
                    .fixedSize()
                Text(row.name)
                    .ledgerFont(.body)
                    .foregroundStyle(LedgerColor.ink)
            }
            Text(row.sub)
                .ledgerFont(.label)
                .foregroundStyle(LedgerColor.inkMuted)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The scheme over the load. Beside the texts it keeps its own width, so that a long name wraps and the
    /// numbers stay whole; under them it has the row's.
    private func prescription(isLargeText: Bool) -> some View {
        VStack(alignment: isLargeText ? .leading : .trailing, spacing: LedgerSpacing.xs) {
            Text(row.scheme)
                .ledgerFont(.numeralS)
                .foregroundStyle(LedgerColor.ink)
            if let load = row.load {
                Text(load)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
        }
        .fixedSize(horizontal: !isLargeText, vertical: false)
    }
}

/// How an exercise's disclosure group is drawn: the row as one plain button under a rule, and the panel under
/// it while the group is expanded. The button is read with the row's spoken label and value.
private struct ExerciseDisclosure: DisclosureGroupStyle {
    let spokenLabel: String
    let spokenValue: String

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            HairlineRule()
            Button { configuration.isExpanded.toggle() } label: { configuration.label }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenLabel)
                .accessibilityValue(spokenValue)
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
