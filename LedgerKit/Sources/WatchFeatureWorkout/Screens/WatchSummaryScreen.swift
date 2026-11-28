import LedgerDesign
import SwiftUI

/// The saved workout (spec §4.3 "Watch — summary"; F18 criterion 11): "WORKOUT DONE" in orange, the workout's time,
/// frozen at its end, over "ELAPSED"; the sets and the volume; the average heart rate from Health, after an orange
/// dot, and the records it set, orange while there is one; and the outlined "Done", which returns to the screen
/// before a workout.
///
/// Nothing on it moves: its time is the model's text. With the wrist down the orange dims and the average heart
/// rate is hidden in its place, as the live screens hide theirs. VoiceOver reads each tile as one phrase. Text too
/// large for the screen scrolls the whole page.
struct WatchSummaryScreen: View {
    let model: WatchSummaryModel
    let send: (WatchAction) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .background(LedgerColor.watchGround)
    }

    var page: some View {
        WatchSummaryPage(screen: self)
    }

    func done() {
        send(.dismissSummary)
    }

    /// NEW PR's number: orange (dimmed with the wrist down) while the workout set a record, else 55 % white.
    static func recordsColor(hasRecords: Bool, isLuminanceReduced: Bool) -> Color {
        hasRecords ? WatchTokens.accent(isLuminanceReduced: isLuminanceReduced) : LedgerColor.watchInkSecondary
    }
}

/// The page itself, at the prototype's measures ÷ 1.5: its 20 px inset is `m`; the spare height spreads the rows.
private struct WatchSummaryPage: View {
    let screen: WatchSummaryScreen
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var model: WatchSummaryModel {
        screen.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.title)
                .ledgerFont(.watchLabel)
                .foregroundStyle(WatchTokens.accent(isLuminanceReduced: isLuminanceReduced))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("workout.summary.title")
            Spacer(minLength: LedgerSpacing.s)
            WatchSummaryTile(
                value: model.elapsed, caption: model.elapsedCaption, spoken: model.spoken.elapsed,
                role: .watchCountdown
            )
            Spacer(minLength: LedgerSpacing.s)
            HStack(alignment: .top, spacing: LedgerSpacing.m) {
                WatchSummaryTile(value: model.sets, caption: model.setsCaption, spoken: model.spoken.sets)
                    .accessibilityIdentifier("workout.summary.sets")
                WatchSummaryTile(value: model.volume, caption: model.volumeCaption, spoken: model.spoken.volume)
            }
            Spacer(minLength: LedgerSpacing.s)
            HStack(alignment: .top, spacing: LedgerSpacing.m) {
                heartRate
                WatchSummaryTile(
                    value: model.records, caption: model.recordsCaption, spoken: model.spoken.records,
                    tint: WatchSummaryScreen.recordsColor(
                        hasRecords: model.hasRecords, isLuminanceReduced: isLuminanceReduced
                    )
                )
            }
            Spacer(minLength: LedgerSpacing.m)
            WatchPill(model.done, style: .outlined, action: screen.done).accessibilityIdentifier("workout.summary.done")
        }
        .padding(.horizontal, LedgerSpacing.m)
        .padding(.vertical, LedgerSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The orange dot before AVG BPM, on the number's baseline; hidden with the wrist down, keeping its place.
    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: WatchTokens.heartGap) {
            Circle()
                .fill(WatchTokens.accent(isLuminanceReduced: isLuminanceReduced))
                .frame(width: WatchTokens.heartDot, height: WatchTokens.heartDot)
            WatchSummaryTile(
                value: model.averageHeartRate, caption: model.averageHeartRateCaption,
                spoken: model.spoken.averageHeartRate
            )
        }
        .privacySensitive()
        .opacity(isLuminanceReduced ? 0 : 1)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One number over its caption, read by VoiceOver as one phrase.
private struct WatchSummaryTile: View {
    let value: String
    let caption: String
    let spoken: String
    var role: LedgerFont.Role = .watchStat
    var tint = LedgerColor.watchInk

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Text(verbatim: value)
                .ledgerFont(role)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: caption)
                .ledgerFont(.watchCaption)
                .foregroundStyle(LedgerColor.watchInkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}
