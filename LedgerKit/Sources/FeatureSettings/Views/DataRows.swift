import LedgerDesign
import SwiftUI

/// "Bar and plates" (criterion 3): a row that opens its sheet, or, while Plate math is off, the same row switched
/// off, without its chevron, its line saying why. VoiceOver reads one button: its title, then its line, dimmed when
/// off.
struct PlatesRow: View {
    let model: PlatesRowModel
    let send: (SettingsAction) -> Void

    var body: some View {
        HairlineRow(model.title, detail: model.detail) {
            if let action = model.action {
                send(action)
            }
        } accessory: {
            // Switched off, the row goes nowhere, so it shows no chevron.
            if model.action != nil {
                LedgerIconView(.chevron, sizedAs: .body)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
        }
        .disabled(model.action == nil)
    }
}

/// "Export data · CSV" (criterion 5, N18): the system's share link over the log as a file, which is written only when
/// the lifter picks where it goes. VoiceOver reads one button, "Export data, CSV", with the row's line as its hint.
struct ExportRow: View {
    let model: SettingsModel.Export

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule()
            ShareLink(item: model.file, preview: SharePreview(model.file.fileName)) {
                HStack(spacing: LedgerSpacing.m) {
                    SettingsRowLabel(title: model.title, detail: model.detail)
                    LedgerIconView(.chevron, sizedAs: .body)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
                .padding(.vertical, LedgerSpacing.l)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.spokenLabel)
            .accessibilityHint(model.detail)
            .accessibilityIdentifier("settings.export")
        }
    }
}
