import SwiftUI

/// The two steppers under the active set (v2): weight and reps, each an outlined pill with "−",
/// the step ("5 LB", "1 REP") and "+". Each "−" and "+" is a 44 pt target. VoiceOver reads each
/// pill as one adjustable element named by its step: swipe up to add, down to take away.
/// At accessibility text sizes the pills stack.
public struct SetRowSteppers: View {
    public enum Direction: Sendable {
        case decrement, increment
    }

    private let weightStep: String
    private let repStep: String
    private let onWeight: (Direction) -> Void
    private let onReps: (Direction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        weightStep: String,
        repStep: String,
        onWeight: @escaping (Direction) -> Void,
        onReps: @escaping (Direction) -> Void
    ) {
        self.weightStep = weightStep
        self.repStep = repStep
        self.onWeight = onWeight
        self.onReps = onReps
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(spacing: LedgerSpacing.s))
        layout {
            StepperPill(step: weightStep, onStep: onWeight)
            StepperPill(step: repStep, onStep: onReps)
        }
        .padding(.bottom, LedgerSpacing.l)
    }
}

/// One outlined stepper: "−", the step, "+".
private struct StepperPill: View {
    let step: String
    let onStep: (SetRowSteppers.Direction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button(.minus, .decrement)
            Text(step)
                .ledgerFont(.eyebrow)
                .foregroundStyle(LedgerColor.inkMuted) // the prototype's .32 is below AA
                .fixedSize()
            button(.plus, .increment)
        }
        .overlay(Capsule.ledgerPill.strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(.increment)
            case .decrement: onStep(.decrement)
            @unknown default: break
            }
        }
    }

    private func button(_ icon: LedgerIcon, _ direction: SetRowSteppers.Direction) -> some View {
        Button {
            onStep(direction)
        } label: {
            LedgerIconView(icon, sizedAs: .subheading)
                .foregroundStyle(LedgerColor.inkSecondary)
                .frame(maxWidth: .infinity)
                .ledgerHitTarget()
        }
        .buttonStyle(LedgerPressStyle())
    }
}
