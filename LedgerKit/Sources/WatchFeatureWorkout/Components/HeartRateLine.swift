import LedgerDesign
import SwiftUI

/// The set screen's heart rate (spec §4.3): an orange dot, the number, then "BPM"; "— BPM" with no sample yet or with
/// Health denied (spec §9). With the wrist down (Always-On, R1 §5.5) the line is hidden and marked privacy-sensitive,
/// keeping its place, so the screen does not shift when the wrist comes up.
///
/// VoiceOver reads one element: "Heart rate, 142 beats per minute", or "Heart rate, No reading".
struct HeartRateLine: View {
    let model: WatchHeartRateModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: WatchTokens.heartGap) {
            Circle()
                .fill(LedgerColor.accent)
                .frame(width: WatchTokens.heartDot, height: WatchTokens.heartDot)
            HStack(alignment: .firstTextBaseline, spacing: WatchTokens.heartGap) {
                Text(verbatim: model.value)
                    .ledgerFont(.watchLabel)
                    .foregroundStyle(LedgerColor.watchInk)
                Text(verbatim: model.unit)
                    .ledgerFont(.watchCaption)
                    .foregroundStyle(LedgerColor.watchInkMuted)
            }
        }
        .privacySensitive()
        .opacity(isLuminanceReduced ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.label))
        .accessibilityValue(Text(verbatim: model.spokenValue))
    }
}
