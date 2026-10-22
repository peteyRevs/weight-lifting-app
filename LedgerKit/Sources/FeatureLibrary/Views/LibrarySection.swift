import LedgerDesign
import SwiftUI

/// One section of the Library: its heading, then its exercises as F06's hairline rows, each under its own rule,
/// and a rule that closes the list (v2).
struct LibrarySection: View {
    let section: LibraryModel.Section
    let send: (LibraryAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(section.title)
            VStack(spacing: 0) {
                ForEach(section.rows) { LibraryRow(row: $0, send: send) }
                HairlineRule()
            }
        }
    }
}

/// One exercise, F06's hairline row as one button: its name, the meta line under it, and its PR at the trailing
/// edge in tabular figures, `inkSecondary` (v2's .72 ink). A tap opens its history. VoiceOver reads the name with
/// the meta and the PR as its value ("Barbell, Chest, 34 sessions, PR 195 pounds"); the drawn "—" is not read.
struct LibraryRow: View {
    let row: LibraryModel.Row
    let send: (LibraryAction) -> Void

    var body: some View {
        HairlineRow(row.name, detail: row.meta) { send(row.action) } accessory: {
            Text(row.record)
                .ledgerFont(.numeralS)
                .foregroundStyle(LedgerColor.inkSecondary)
        }
        .accessibilityLabel(row.name)
        .accessibilityValue(row.spokenValue)
    }
}
