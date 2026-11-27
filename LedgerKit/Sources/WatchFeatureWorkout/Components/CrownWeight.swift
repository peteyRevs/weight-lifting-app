import LedgerDesign
import SwiftUI

/// The set screen's weight (spec §4.3 "Watch — set ready"; F18 criteria 4 and 14): the numeral in the watch's big
/// figures beside its unit, turned by the Digital Crown (R1 D10). Each detent is the exercise's step; the number moves
/// with the binding, on the next frame, and `onIdle` ends the turn, which the store commits once (`CrownWeightModel`).
/// Four digits fit at the default text size; a number too wide for its row shrinks, never below the 11 pt floor.
///
/// VoiceOver reads one adjustable element, "Weight, 185 pounds": a swipe up or down takes one step and commits it, as
/// a turn that comes to rest does. Strings come from the dial (`WatchPresentation.crownDial`).
struct CrownWeight: View {
    let dial: CrownDial
    /// The crown's binding is written through `onRotate` (`WatchAction.crownRotated`); `onRest` is its `onIdle`
    /// (`.crownRested`).
    let onRotate: (Double) -> Void
    let onRest: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let size = LedgerFont.scaledSize(.watchNumeral, dynamicTypeSize: dynamicTypeSize)
        HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.xs) {
            Text(verbatim: dial.weight)
                .ledgerFont(.watchNumeral)
                .foregroundStyle(LedgerColor.watchInk)
                .lineLimit(1)
                .minimumScaleFactor(LedgerFont.shrinkLimit(.watchNumeral, size: size))
            Text(verbatim: dial.unit)
                .ledgerFont(.watchLabel)
                .foregroundStyle(LedgerColor.watchInkMuted)
                .fixedSize()
        }
        .modifier(CrownRotation(weight: self))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: dial.label))
        .accessibilityValue(Text(verbatim: dial.spokenWeight))
        .accessibilityAdjustableAction(adjust)
    }

    /// The crown's binding: the dial's position, written through `onRotate`.
    var rotation: Binding<Double> {
        Binding(get: { dial.value }, set: onRotate)
    }

    /// A VoiceOver swipe: one step up or down, inside the crown's range, then at rest.
    func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let step: Double = switch direction {
        case .increment: dial.step
        case .decrement: -dial.step
        @unknown default: 0
        }
        onRotate(min(max(dial.value + step, 0), dial.upperBound))
        onRest()
    }
}

/// `digitalCrownRotation(detent:…)` as R1 D10 sets it, on a focusable view without the focus ring the prototype does
/// not draw: from 0, so the first turn down from a light weight meets no clamp, through the dial's top.
private struct CrownRotation: ViewModifier {
    let weight: CrownWeight

    func body(content: Content) -> some View {
        #if os(watchOS)
            content
                .focusable()
                .focusEffectDisabled()
                .digitalCrownRotation(
                    detent: weight.rotation,
                    from: 0,
                    through: weight.dial.upperBound,
                    by: weight.dial.step,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true,
                    onIdle: weight.onRest
                )
        #else
            content
        #endif
    }
}
