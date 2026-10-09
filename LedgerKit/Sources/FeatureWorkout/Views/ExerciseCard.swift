import LedgerDesign
import SwiftUI

/// The shown exercise (v2 "Active workout"; the TARGET line is v1's, which v2 does not draw): its place and
/// name, what the program prescribes, what was done last time with "Repeat", the set rows, and "+ Add set".
/// v2 draws it on the ground with no card behind it, and so does this.
///
/// The page's one orange is the shown row's (`SetRow`'s `active` state: its label, its rule and its check's
/// ring); the eyebrow, "TARGET" and "Repeat" are ink.
struct ExerciseCard: View {
    let model: ExerciseCardModel
    let send: (WorkoutEdit) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.eyebrow)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted)
                Text(model.title)
                    .ledgerFont(.heading)
                    .foregroundStyle(LedgerColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("workout.card.title")
            }
            VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                FactLine(label: model.targetLabel, value: model.target)
                    .ledgerHitTarget(alignment: .leading)
                last
            }
            VStack(alignment: .leading, spacing: 0) {
                SetRowList(model: model, send: send)
                PillButton(model.addSet, style: .ghost, flush: .leading) {
                    send(.addSet(exerciseIndex: model.exerciseIndex))
                }
                .accessibilityIdentifier("workout.card.addSet")
            }
        }
    }

    /// "Last", the line, and "Repeat" when there is a last workout to repeat. The line and its label are one
    /// stop; the button is its own.
    private var last: some View {
        HStack(spacing: LedgerSpacing.m) {
            FactLine(label: model.lastLabel, value: model.last)
            Spacer(minLength: 0)
            if let title = model.repeatLast {
                PillButton(title) { send(.repeatLast(exerciseIndex: model.exerciseIndex)) }
                    .accessibilityIdentifier("workout.card.repeat")
            }
        }
        .ledgerHitTarget(alignment: .leading)
    }
}

/// A label and its value ("TARGET" and what is prescribed, "Last" and what was done), read as one stop. Side
/// by side, and one over the other at the accessibility sizes, where a line of numbers needs the whole
/// width. A value too long for its line wraps; it is never cut.
struct FactLine: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LedgerSpacing.m))
        layout {
            Text(label)
                .ledgerFont(.label)
                .foregroundStyle(LedgerColor.inkMuted)
            Text(value)
                .ledgerFont(.caption)
                .foregroundStyle(LedgerColor.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
