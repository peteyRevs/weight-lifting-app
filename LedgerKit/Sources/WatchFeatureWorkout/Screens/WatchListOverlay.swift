import LedgerDesign
import SwiftUI

/// The session list (spec §4.3 "Watch — session list"; F18 criteria 8 and 9), over the live workout in its place, as
/// the prototype draws it: the orange "‹", which closes it, beside "{done} OF {n} DONE"; a row per exercise, which
/// selects it and closes the list; and the outlined "End workout", which opens the end overlay. A list taller than the
/// screen scrolls whole, with the crown, as the watch's lists do, so "End workout" follows the last row. The store
/// closes the list on a change of mode (spec §4.2).
struct WatchListOverlay: View {
    let model: WatchListModel
    let send: (WatchAction) -> Void
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .background(LedgerColor.watchGround)
    }

    /// The whole list: the header, the rows and "End workout".
    var page: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            header
            ForEach(model.rows, id: \.exerciseIndex) { row in
                WatchListRow(row: row, accent: accent) { select(row.exerciseIndex) }
                    .accessibilityIdentifier("workout.list.row.\(row.exerciseIndex)")
            }
            WatchPill(model.endWorkout, style: .outlined, action: openEnd)
                .accessibilityIdentifier("workout.list.end")
                .padding(.top, LedgerSpacing.xs)
        }
        .padding(.horizontal, LedgerSpacing.s)
        .padding(.vertical, LedgerSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accent: Color {
        WatchTokens.accent(isLuminanceReduced: isLuminanceReduced)
    }

    private var header: some View {
        HStack(spacing: LedgerSpacing.s) {
            Button(action: close) {
                LedgerIconView(.chevron, sizedAs: .watchLabel)
                    .scaleEffect(x: -1) // "‹": the chevron points back, in either reading direction
                    .foregroundStyle(accent)
                    .frame(minWidth: WatchTokens.stepButton, minHeight: WatchTokens.stepButton, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: WatchWorkoutCopy.closeList))
            .accessibilityIdentifier("workout.list.close")
            Text(verbatim: model.header)
                .ledgerFont(.watchLabel)
                .foregroundStyle(LedgerColor.watchInkSecondary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    func close() {
        send(.closeList)
    }

    func select(_ exerciseIndex: Int) {
        send(.selectExercise(exerciseIndex))
    }

    func openEnd() {
        send(.openEnd)
    }
}

/// One exercise: its number, orange when current; its name, dimmed once done; its scheme; and an orange check once
/// every set is logged. The current row has the orange 16 % fill and the orange border, the others a 14 % rule.
private struct WatchListRow: View {
    let row: WatchListModel.Row
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LedgerSpacing.s) {
                Text(verbatim: row.number)
                    .ledgerFont(.watchLabel)
                    .foregroundStyle(row.isCurrent ? accent : LedgerColor.watchInkMuted)
                VStack(alignment: .leading, spacing: WatchTokens.rowGap) {
                    Text(verbatim: row.name)
                        .ledgerFont(.watchTitle)
                        .foregroundStyle(row.isDone ? LedgerColor.watchInkSecondary : LedgerColor.watchInk)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: row.scheme)
                        .ledgerFont(.watchCaption)
                        .foregroundStyle(LedgerColor.watchInkMuted)
                }
                Spacer(minLength: 0)
                if row.isDone {
                    LedgerIconView(.check, sizedAs: .watchLabel)
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, LedgerSpacing.s)
            .padding(.vertical, LedgerSpacing.s)
            .frame(maxWidth: .infinity, minHeight: WatchTokens.rowHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: WatchTokens.rowRadius)
                    .fill(row.isCurrent ? WatchTokens.accentFill : .clear)
                    .strokeBorder(row.isCurrent ? accent : LedgerColor.watchHairline, lineWidth: LedgerHairline.width)
            }
            .contentShape(RoundedRectangle(cornerRadius: WatchTokens.rowRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: row.isDone ? WatchWorkoutCopy.allSetsLogged : ""))
        .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
    }
}
