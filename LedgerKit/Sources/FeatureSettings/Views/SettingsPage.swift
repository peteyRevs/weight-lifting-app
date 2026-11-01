import LedgerDesign
import SwiftUI

/// Everything Settings scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees and the
/// snapshot references are taken from. Top to bottom: the title, with the failed save's line under it when there is
/// one; TRAINING (Units, Default rest, Week starts on and the three switches); DATA (Apple Health and, in Debug
/// builds, Diagnostics); then the About line.
///
/// Each section is hairline rows on the ground, as the Library's are, not the prototype's white cards (v2). Its
/// 22 px between the title and the first section, and between sections, is `xl` (24), the scale's nearest step.
struct SettingsPage: View {
    let model: SettingsModel
    let send: (SettingsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                SettingsHeader(title: model.title)
                if let problem = model.problem {
                    Text(problem)
                        .ledgerFont(.bodyLight)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
            }
            SettingsSection(title: model.training) {
                UnitsRow(units: model.units, send: send)
                RestRow(rest: model.rest, send: send)
                WeekStartRow(weekStart: model.weekStart, send: send)
                ForEach(model.switches) { SwitchRow(model: $0, send: send) }
            }
            SettingsSection(title: model.data) {
                HairlineRow(model.health.title) {
                    Text(model.health.value)
                        .ledgerFont(.label)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
                if let diagnostics = model.diagnostics {
                    HairlineRow(diagnostics.title) { send(diagnostics.action) } accessory: {
                        LedgerIconView(.chevron, sizedAs: .body)
                            .foregroundStyle(LedgerColor.inkMuted)
                    }
                }
            }
            Text(model.about)
                .ledgerFont(.label)
                .foregroundStyle(LedgerColor.inkMuted)
        }
        .padding(LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The title: the screen's heading, and the element the UI tests find (`settings.title`). The root draws it alone
/// until the settings are read.
struct SettingsHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .ledgerFont(.title)
            .foregroundStyle(LedgerColor.ink)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("settings.title")
    }
}
