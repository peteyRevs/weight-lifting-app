import LedgerDesign
import SwiftUI

/// Everything Settings scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees and the
/// snapshot references are taken from. Top to bottom: the title, with the failed save's line under it when there is
/// one, and "Try again" under a failed switch of units; TRAINING (Units, Default rest, Week starts on, the three
/// switches and Bar and plates); DATA (Apple Health, Export data · CSV and, in Debug builds, Diagnostics); then the
/// About line.
///
/// Each section is hairline rows on the ground, as the Library's are, not the prototype's white cards (v2). Its
/// 22 px between the title and the first section, and between sections, is `xl` (24), the scale's nearest step.
struct SettingsPage: View {
    let model: SettingsModel
    let send: (SettingsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            SettingsTop(model: model, send: send)
            SettingsSection(title: model.training) {
                UnitsRow(units: model.units, send: send)
                RestRow(rest: model.rest, send: send)
                WeekStartRow(weekStart: model.weekStart, send: send)
                ForEach(model.switches) { SwitchRow(model: $0, send: send) }
                PlatesRow(model: model.plates, send: send)
            }
            SettingsSection(title: model.data) {
                HairlineRow(model.health.title) {
                    Text(model.health.value)
                        .ledgerFont(.label)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
                ExportRow(model: model.export)
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

/// The top of the page: the title, the line of a save that failed under it, and "Try again" under a failed switch of
/// units.
struct SettingsTop: View {
    let model: SettingsModel
    let send: (SettingsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            SettingsHeader(title: model.title)
            if let problem = model.problem {
                Text(problem)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
            if let retry = model.retry {
                PillButton(retry.title, flush: .leading) { send(retry.action) }
            }
        }
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
