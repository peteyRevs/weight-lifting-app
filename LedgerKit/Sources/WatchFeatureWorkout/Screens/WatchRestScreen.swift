import LedgerDesign
import SwiftUI

/// The rest (spec §4.3 "Watch — rest timer", §4.5 as F18 resolves it; criteria 5–7, 12, 14 and 15): the title,
/// "REST", or "GO" for the moment after zero, over the ring, which drains as the countdown runs, with the heart rate
/// and the next set inside it, and "+30s" and the orange "Skip" at the bottom.
///
/// **Time.** The countdown is a `Text(timerInterval:)`, which ticks by itself, with the wrist down too; the ring and
/// what VoiceOver reads for it are read again by a `TimelineView` on the rest's own seconds, and once a minute with
/// the wrist down (criterion 12). The screen keeps no timer of its own, and the store moves the mode at the edges.
///
/// **GO.** At zero the screen shakes three times, as the prototype buzzes, beside the haptic the store plays; under
/// Reduce Motion it does not move, and the haptic is unchanged (criterion 15). With the wrist down the orange dims
/// and the heart rate is hidden in its place. Text too large for the screen scrolls the whole page.
struct WatchRestScreen: View {
    let model: WatchRestModel
    let send: (WatchAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shaken = 0.0

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .modifier(WatchBuzzShake(cycles: shaken))
        .background(LedgerColor.watchGround)
        .onChange(of: model.isOver) { _, isOver in
            if Self.shakes(atRestOver: isOver, reduceMotion: reduceMotion) {
                withAnimation(.easeInOut(duration: WatchBuzzShake.duration)) { shaken += WatchBuzzShake.shakes }
            }
        }
    }

    var page: some View {
        WatchRestPage(screen: self)
    }

    /// Whether the screen shakes as it turns to `isOver`: at "GO", and never under Reduce Motion (criterion 15).
    static func shakes(atRestOver isOver: Bool, reduceMotion: Bool) -> Bool {
        isOver && !reduceMotion
    }

    func extend() {
        send(.extendRest)
    }

    func skip() {
        send(.skipRest)
    }
}

/// The page itself, at the prototype's measures ÷ 1.5.
private struct WatchRestPage: View {
    let screen: WatchRestScreen
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.watchTimeline) private var timeline

    private var model: WatchRestModel {
        screen.model
    }

    /// When the rest began: the countdown counts from it, and the ring is read again on its seconds.
    private var start: Date {
        model.timer.endsAt.addingTimeInterval(-(model.timer.total / .seconds(1)))
    }

    var body: some View {
        VStack(spacing: LedgerSpacing.xs) {
            Text(verbatim: model.title)
                .ledgerFont(.watchLabel)
                .foregroundStyle(WatchTokens.accent(isLuminanceReduced: isLuminanceReduced))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("workout.rest.title")
            model.connection.map { line in
                Text(verbatim: line)
                    .ledgerFont(.watchTitle)
                    .foregroundStyle(LedgerColor.watchInkSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: start, by: isLuminanceReduced ? 60 : 1)) { context in
                let now = timeline.moment(context.date)
                WatchRestRing(
                    progress: model.timer.fraction(at: now),
                    label: timeline.timer(from: start, to: model.timer.endsAt, countsDown: true, fallback: model.clock),
                    accessibilitySummary: model.ringSummary(at: now)
                ) { footer }
            }
            Spacer(minLength: 0)
            HStack(spacing: LedgerSpacing.s) {
                WatchPill(WatchWorkoutCopy.extendRest, style: .outlined, action: screen.extend)
                    .accessibilityLabel(Text(verbatim: WatchWorkoutCopy.extendRestLabel))
                    .accessibilityIdentifier("workout.rest.extend")
                WatchPill(WatchWorkoutCopy.skipRest, action: screen.skip).accessibilityIdentifier("workout.rest.skip")
            }
        }
        .padding(.horizontal, LedgerSpacing.m)
        .padding(.vertical, LedgerSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Inside the ring, under the countdown: the heart rate, hidden with the wrist down, and the next set, which
    /// wraps in the ring's narrowing chord rather than be cut.
    private var footer: some View {
        VStack(spacing: WatchTokens.rowGap) {
            HStack(spacing: WatchTokens.heartGap) {
                Circle()
                    .fill(LedgerColor.accent)
                    .frame(width: WatchTokens.heartDot, height: WatchTokens.heartDot)
                Text(verbatim: model.heartRate)
                    .ledgerFont(.watchLabel)
                    .foregroundStyle(LedgerColor.watchInkSecondary)
            }
            .privacySensitive()
            .opacity(isLuminanceReduced ? 0 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: model.heartRateLine.label))
            .accessibilityValue(Text(verbatim: model.heartRateLine.spokenValue))
            .accessibilityAddTraits(.isStaticText)
            Text(verbatim: model.next)
                .ledgerFont(.watchTitle)
                .foregroundStyle(LedgerColor.watchInkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
