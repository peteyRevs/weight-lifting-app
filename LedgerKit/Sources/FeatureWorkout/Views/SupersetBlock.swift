import LedgerDesign
import SwiftUI

/// A superset drawn as one block (F10 S9; spec §3.7, v1's legend; v2 draws no superset): the block's place,
/// the round as the heading, one legend row per member with the group's rest under them, the current
/// member's "Last" and "Repeat", every row of the block in round order, and "+ Add set" for the current
/// member. Like the card, it stands on the ground with no card behind it.
///
/// What is orange: the shown row (`SetRow`'s `active` state), as on the card, and the current member's
/// letter on its ink-filled legend row (v1's mark). The eyebrow, the rest line, "Repeat" and the swap
/// buttons are ink.
///
/// VoiceOver reads the eyebrow, the title (a heading), each legend row as one stop followed by its swap
/// button, the rest line with its time in words, "Last" and "Repeat", the rows each with its check, the
/// steppers after the shown row, and "+ Add set".
struct SupersetBlock: View {
    let model: SupersetBlockModel
    let send: (WorkoutAction) -> Void

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
                    .accessibilityIdentifier("workout.block.title")
            }
            legend
            if let current = model.current {
                last(of: current)
            }
            VStack(alignment: .leading, spacing: 0) {
                SetRowList(rows: model.rows, columns: model.columns, steppers: model.steppers) { send(.edit($0)) }
                if let current = model.current {
                    PillButton(model.addSet, style: .ghost, flush: .leading) {
                        send(.edit(.addSet(exerciseIndex: current.exerciseIndex)))
                    }
                    .accessibilityIdentifier("workout.block.addSet")
                }
            }
        }
    }

    /// The members, then the group's rest, read with its time in words.
    private var legend: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            ForEach(model.legend) { row in
                SupersetLegendRow(row: row, send: send)
            }
            Text(model.restLine)
                .ledgerFont(.caption)
                .foregroundStyle(LedgerColor.inkMuted)
                .accessibilityLabel(model.restLineSpoken)
        }
    }

    /// The current member's "Last" and "Repeat", as the card draws them.
    private func last(of current: SupersetBlockModel.CurrentMember) -> some View {
        HStack(spacing: LedgerSpacing.m) {
            FactLine(label: current.lastLabel, value: current.last)
            Spacer(minLength: 0)
            if let title = current.repeatLast {
                PillButton(title) { send(.edit(.repeatLast(exerciseIndex: current.exerciseIndex))) }
                    .accessibilityIdentifier("workout.block.repeat")
            }
        }
    }
}

/// One member on the legend: its letter, its name and its target, one button that shows the member, and
/// "Swap exercise" beside it while the member can be swapped (a sibling, never inside the row's button).
/// The current member is drawn ink-filled with an orange letter (v1); the others on the surface.
///
/// At the accessibility sizes the target stands under the name and the swap button under both, so the name
/// keeps the width. VoiceOver reads the row, then its swap button, whatever the layout puts higher: the
/// button sorts after the row (as `ExerciseCardTitleRow` does).
struct SupersetLegendRow: View {
    let row: SupersetBlockModel.LegendRow
    let send: (WorkoutAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let outer = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LedgerSpacing.s))
        return outer {
            Button {
                send(.edit(.jump(exerciseIndex: row.exerciseIndex)))
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.spoken)
            .accessibilityAddTraits(row.isCurrent ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("workout.block.legend.\(row.letter)")
            if let swap = row.swap {
                IconPillButton(swap, icon: .swap) {
                    send(.swap(.open(exerciseIndex: row.exerciseIndex, exerciseID: row.exerciseID)))
                }
                .accessibilityIdentifier("workout.block.swap.\(row.letter)")
                .accessibilitySortPriority(-1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The letter, the name and the target on the row's fill: side by side, the target under the name at the
    /// accessibility sizes.
    private var label: some View {
        let inner = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LedgerSpacing.m))
        return inner {
            HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.m) {
                Text(row.letter)
                    .ledgerFont(.numeralS)
                    .foregroundStyle(row.isCurrent ? LedgerColor.accent : LedgerColor.inkFaint)
                Text(row.name)
                    .ledgerFont(.body)
                    .foregroundStyle(row.isCurrent ? LedgerColor.ground : LedgerColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(row.target)
                .ledgerFont(.caption)
                .foregroundStyle(row.isCurrent ? LedgerColor.ground : LedgerColor.inkMuted)
        }
        .padding(LedgerSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ledgerHitTarget(alignment: .leading)
        .background(
            row.isCurrent ? LedgerColor.ink : LedgerColor.surface,
            in: RoundedRectangle(cornerRadius: LedgerRadius.row, style: .continuous)
        )
    }
}
