import LedgerDesign
import SwiftUI

/// The shown exercise (v2 "Active workout"; the TARGET line is v1's, which v2 does not draw): its place and
/// name, what the program prescribes, what was done last time with "Repeat", the set rows, and "+ Add set".
/// v2 draws it on the ground with no card behind it, and so does this.
///
/// The page's one orange is the shown row's (`SetRow`'s `active` state: its label, its rule and its check's
/// ring); the eyebrow, "TARGET", "Repeat" and the swap button are ink.
struct ExerciseCard: View {
    let model: ExerciseCardModel
    let send: (WorkoutAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            ExerciseCardTitleRow(model: model, send: send)
            // More room between the two facts than inside one (`FactLine` stacks with `xs`), so that at every
            // size "Last" stands nearer its own value than the target's.
            VStack(alignment: .leading, spacing: LedgerSpacing.m) {
                FactLine(label: model.targetLabel, value: model.target)
                last
            }
            VStack(alignment: .leading, spacing: 0) {
                SetRowList(rows: model.rows, columns: model.columns, steppers: model.steppers) { send(.edit($0)) }
                PillButton(model.addSet, style: .ghost, flush: .leading) {
                    send(.edit(.addSet(exerciseIndex: model.exerciseIndex)))
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
                PillButton(title) { send(.edit(.repeatLast(exerciseIndex: model.exerciseIndex))) }
                    .accessibilityIdentifier("workout.card.repeat")
            }
        }
    }
}

/// The place and the name, with "Swap exercise" at the trailing edge, level with the top of the place
/// (v2), while the exercise can be swapped. At the accessibility sizes the button stands under the name,
/// so the name keeps the whole width and never wraps under the button.
///
/// VoiceOver reads the place and the name, then the button, whatever the layout puts higher (criterion 32;
/// F10-S8b-G2-2): the row is a container, and the button sorts after the place and the name (priority −1
/// against their default 0), not by position (a wrapped name starts below the button's top). Only the
/// button carries a priority, so a card without it reads as before.
///
/// The place and the name are not a container of their own inside the row. With one, once the card moved
/// on to the next exercise, XCUITest's hit test at the name no longer found it: the nightly `WorkoutLogging`
/// test's "the next exercise's name is on screen" failed with the name drawn at the top of the page. That
/// test is the pin. No hosted test can be: in a package test process `accessibilityHitTest(_:event:)`
/// answers nil at every point, the card's name before the move included, likely because UIKit's accessibility
/// runtime is not loaded there (`chore(test)` fix round 2, 2026-11-12). Whether VoiceOver's touch
/// exploration missed the name too was not shown.
struct ExerciseCardTitleRow: View {
    let model: ExerciseCardModel
    let send: (WorkoutAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LedgerSpacing.m))
        return layout {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            if let swap = model.swap {
                IconPillButton(swap, icon: .swap) {
                    send(.swap(.open(exerciseIndex: model.exerciseIndex, exerciseID: model.exerciseID)))
                }
                .accessibilityIdentifier("workout.card.swap")
                .accessibilitySortPriority(-1)
            }
        }
        .accessibilityElement(children: .contain)
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
