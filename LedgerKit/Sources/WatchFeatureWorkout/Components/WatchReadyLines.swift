import LedgerDesign
import SwiftUI

/// The set screen's top line: the set label in orange, the screen's heading (dimmed with the wrist down), and the
/// workout's time, which counts by itself.
struct WatchReadyHeader: View {
    let model: WatchReadyModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.watchTimeline) private var timeline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.xs) {
            Text(verbatim: model.setLabel)
                .ledgerFont(.watchLabel)
                .foregroundStyle(WatchTokens.accent(isLuminanceReduced: isLuminanceReduced))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            timeline.timer(from: model.startedAt, countsDown: false, fallback: model.elapsed)
                .ledgerFont(.watchCaption)
                .foregroundStyle(LedgerColor.watchInkMuted)
                .accessibilityLabel(Text(verbatim: WatchWorkoutCopy.elapsedLabel))
        }
    }
}

/// The set screen's "× 5 REPS" and its target, "RPE 8", read as one line.
struct WatchRepsLine: View {
    let model: WatchReadyModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.xs) {
            Text(verbatim: model.reps)
                .ledgerFont(.watchStat)
                .foregroundStyle(LedgerColor.watchInk)
            Text(verbatim: WatchWorkoutCopy.repsCaption)
                .ledgerFont(.watchCaption)
                .foregroundStyle(LedgerColor.watchInkMuted)
            Spacer(minLength: 0)
            Text(verbatim: model.target)
                .ledgerFont(.watchCaption)
                .foregroundStyle(LedgerColor.watchInkMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
