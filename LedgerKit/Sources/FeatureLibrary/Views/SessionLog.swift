import LedgerDesign
import SwiftUI

/// SESSION LOG: each session as one F06 hairline row that opens its workout, with its date, its tag at the
/// trailing edge and its sets under the date; or "No sessions yet.". A PR tag is bold, so it is never told by
/// colour, and wears no orange (Pete's question 3: the estimate, the change and the last bar only). VoiceOver
/// reads the date, then the tag and the sets.
struct SessionLog: View {
    let log: ExerciseHistoryModel.Log
    let send: (LibraryRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(log.title)
            if let empty = log.empty {
                Text(empty)
                    .ledgerFont(.bodyLight)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
            HairlineList {
                ForEach(log.entries) { entry in
                    HairlineRow(entry.date, detail: entry.sets) { send(entry.route) } accessory: {
                        Text(entry.tag)
                            .ledgerFont(entry.isRecord ? .numeralS : .label)
                            .foregroundStyle(entry.isRecord ? LedgerColor.ink : LedgerColor.inkSecondary)
                    }
                    .accessibilityLabel(entry.date)
                    .accessibilityValue(entry.spokenValue)
                }
            }
        }
    }
}
