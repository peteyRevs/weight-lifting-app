import LedgerDesign
import LedgerDomain
import SwiftUI

/// The set to log (spec §4.3 "Watch — set ready"; F18 criteria 2–4, 12 and 14), drawn from its model and the crown's
/// dial: the set label in orange and the workout's time at the top; the exercise's name, which opens the session
/// list; the weight the crown turns beside the set dots; the reps and the target; the heart rate beside "−" and "+"
/// for the reps; and the orange "Done set" at the bottom. With Health denied, a line asks for it once (spec §9).
///
/// The time counts by itself (`Text(timerInterval:)`). With the wrist down the orange dims, the dots are outlined and
/// the heart rate is hidden in its place, so nothing moves. Text too large for the screen scrolls the whole page, as
/// the screen before a workout does; the crown stays the weight's, which holds the focus.
struct WatchReadyScreen: View {
    let model: WatchReadyModel
    /// The crown's weight; nil with no set left to change, when the weight is drawn still.
    let dial: CrownDial?
    let send: (WatchAction) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .background(LedgerColor.watchGround)
    }

    var page: some View {
        WatchReadyPage(screen: self)
    }

    /// "−" at one rep would change nothing, so it is drawn disabled there.
    var canDecreaseReps: Bool {
        model.repsValue > 1
    }

    func logSet() {
        send(.logSet)
    }

    func openList() {
        send(.openList)
    }

    func decreaseReps() {
        send(.stepReps(.downward))
    }

    func increaseReps() {
        send(.stepReps(.upward))
    }

    func rotate(_ value: Double) {
        send(.crownRotated(value))
    }

    func restCrown() {
        send(.crownRested)
    }
}

/// The page itself, at the prototype's measures ÷ 1.5: its 20 px inset is `m`, and its rows stand 3 px apart. Its
/// lines stand close so that the page fits a 42 mm screen; the spare height goes above the weight and the pill.
private struct WatchReadyPage: View {
    let screen: WatchReadyScreen

    private var model: WatchReadyModel {
        screen.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTokens.rowGap) {
            WatchReadyHeader(model: model)
            model.connection.map(line)
            name
            Spacer(minLength: LedgerSpacing.xs)
            HStack(alignment: .bottom, spacing: LedgerSpacing.xs) {
                weight
                Spacer(minLength: 0)
                SetDots(dots: model.dots, accessibilitySummary: model.dotsSummary)
                    .padding(.bottom, LedgerSpacing.xs)
            }
            WatchRepsLine(model: model).accessibilityIdentifier("workout.ready.reps")
            HStack(spacing: LedgerSpacing.xs) {
                HeartRateLine(model: model.heartRate).accessibilityIdentifier("workout.ready.heartRate")
                Spacer(minLength: 0)
                WatchStepButton(icon: .minus, label: WatchWorkoutCopy.decreaseReps, action: screen.decreaseReps)
                    .disabled(!screen.canDecreaseReps)
                    .accessibilityIdentifier("workout.ready.reps.decrease")
                WatchStepButton(icon: .plus, label: WatchWorkoutCopy.increaseReps, action: screen.increaseReps)
                    .accessibilityIdentifier("workout.ready.reps.increase")
            }
            model.healthLine.map(line)
            Spacer(minLength: LedgerSpacing.xs)
            WatchPill(WatchWorkoutCopy.doneSet, action: screen.logSet).accessibilityIdentifier("workout.ready.doneSet")
        }
        .padding(.horizontal, LedgerSpacing.m)
        .padding(.vertical, LedgerSpacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// How far the name's tap area reaches above and below its line, which the layout does not see: the line alone is
    /// smaller than the 44 px (29 pt) the watch's other targets take (the audit's "Hit area is too small").
    private static let nameReach: CGFloat = LedgerSpacing.xs * 2

    /// The exercise's name and "›": a tap opens the session list.
    private var name: some View {
        Button(action: screen.openList) {
            HStack(spacing: LedgerSpacing.xs) {
                Text(verbatim: model.exerciseName)
                    .ledgerFont(.watchTitle)
                    .foregroundStyle(LedgerColor.watchInk)
                    .multilineTextAlignment(.leading)
                LedgerIconView(.chevron, sizedAs: .watchTitle)
                    .foregroundStyle(LedgerColor.watchInkMuted)
            }
            .padding(.vertical, Self.nameReach)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -Self.nameReach)
        .accessibilityIdentifier("workout.ready.exercise")
    }

    /// The weight the crown turns, or, with no set left to change, the shown set's weight, still.
    @ViewBuilder private var weight: some View {
        if let dial = screen.dial {
            CrownWeight(dial: dial, onRotate: screen.rotate, onRest: screen.restCrown)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.xs) {
                Text(verbatim: model.weight).ledgerFont(.watchNumeral).foregroundStyle(LedgerColor.watchInk)
                Text(verbatim: model.unit).ledgerFont(.watchLabel).foregroundStyle(LedgerColor.watchInkMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// A line of words under the set label or the heart rate: the connection, or the one-time ask for Health.
    private func line(_ text: String) -> some View {
        Text(verbatim: text)
            .ledgerFont(.watchTitle)
            .foregroundStyle(LedgerColor.watchInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
