import LedgerDesign
import SwiftUI

/// The cover's pinned header (v2 "Active workout"): "Minimize", the orange dot and the elapsed time, and
/// "Finish" in one row; under it the workout's name (v1's eyebrow; v2 draws none) and one progress segment
/// per exercise.
///
/// The elapsed time counts by the wall clock from the workout's start (`WorkoutTimeline`), so the model is
/// not rebuilt each second. VoiceOver reads its name and no time: a spoken time would be as old as the last
/// time the header was drawn. v2's 14 px time is `numeralS` (the spec's "Elapsed timer", 700 15 px,
/// tabular); its 18 px between the row and the bars is `l` (16).
struct WorkoutHeader: View {
    let model: WorkoutHeaderModel
    let send: (WorkoutAction) -> Void
    @Environment(\.workoutTimeline) private var timeline

    /// The prototype's 5 px dot.
    private static let dot: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            HStack(spacing: LedgerSpacing.s) {
                PillButton(model.minimize, style: .ghost, flush: .leading) { send(.minimize) }
                    .disabled(!model.isEnabled)
                    .accessibilityIdentifier("workout.header.minimize")
                Spacer(minLength: 0)
                elapsed
                Spacer(minLength: 0)
                PillButton(model.finish) { send(.finish) }
                    .disabled(!model.isEnabled)
                    .accessibilityIdentifier("workout.header.finish")
            }
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Eyebrow(model.title)
                    .accessibilityIdentifier("workout.header.title")
                ProgressSegments(model.segments, label: model.progressLabel, value: model.progressValue)
                    .accessibilityIdentifier("workout.header.progress")
            }
        }
    }

    private var elapsed: some View {
        HStack(spacing: LedgerSpacing.s) {
            Circle()
                .fill(LedgerColor.accent)
                .frame(width: Self.dot, height: Self.dot)
            timeline.elapsed(since: model.startedAt)
                .ledgerFont(.numeralS)
                .foregroundStyle(LedgerColor.ink)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.elapsedLabel)
        .accessibilityIdentifier("workout.header.elapsed")
    }
}
