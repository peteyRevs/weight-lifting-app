import LedgerDesign
import SwiftUI

/// One section of Settings: its heading, then its rows, each under its own rule, and a rule that closes the list
/// (v2's hairline rows, as the Library's sections).
struct SettingsSection<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(title)
            VStack(spacing: 0) {
                rows
                HairlineRule()
            }
        }
    }
}

/// A row of a section that holds a control: under its rule, with `HairlineRow`'s padding.
struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()
            content
                .padding(.vertical, LedgerSpacing.l)
        }
    }
}

/// A row's title over its line, as `HairlineRow` draws them, for the rows whose control speaks for them: VoiceOver
/// reads the control, with the line as its hint, so these two are hidden from it.
struct SettingsRowLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Text(title).ledgerFont(.body).foregroundStyle(LedgerColor.ink)
            Text(detail).ledgerFont(.label).foregroundStyle(LedgerColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// A label and its control side by side, and at accessibility text sizes the control under the label, so neither
/// has to squeeze (the `HairlineRow` and `StepperField` rule, N10).
struct SettingsRowLayout<Label: View, Control: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let control: Control
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(spacing: LedgerSpacing.m))
        layout {
            label
            control
        }
    }
}
