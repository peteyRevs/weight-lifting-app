import SwiftUI

/// One field of a form that is stepped, not typed (the Day editor's "Sets", "Start load", "Rest"; Settings'
/// default rest): its label, its value, and "−" and "+", each a 44 pt target.
///
/// It takes `String`s and one closure per step and looks nothing up. A step whose closure is nil is switched
/// off, as for a value at its limit: its button is drawn faint and does nothing.
///
/// VoiceOver reads the field as one adjustable element, the label with the value (`spokenValue` when the drawn
/// value is not what should be heard, "2:30" against "2 minutes 30 seconds"): swipe up for "+", down for "−",
/// and it announces the value the caller passes back. A swipe towards a switched-off step changes nothing,
/// and one step off is not spoken: there is no trait for one direction. With both steps off, or the field
/// disabled, the element is dimmed, and the label and the value are drawn in the faint ink a disabled pill's
/// text takes.
///
/// At accessibility text sizes the buttons stand under the label and the value.
public struct StepperField: View {
    private let label: String
    private let value: String
    private let spokenValue: String?
    private let onDecrement: (() -> Void)?
    private let onIncrement: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ label: String,
        value: String,
        spokenValue: String? = nil,
        onDecrement: (() -> Void)?,
        onIncrement: (() -> Void)?
    ) {
        self.label = label
        self.value = value
        self.spokenValue = spokenValue
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(spacing: LedgerSpacing.m))
        // With no step to take the field is disabled, whoever switched it off: the modifier below.
        let isLive = isEnabled && (onDecrement != nil || onIncrement != nil)
        layout {
            VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                Text(label)
                    .ledgerFont(.label)
                    .foregroundStyle(isLive ? LedgerColor.inkMuted : LedgerColor.inkFaint)
                Text(value)
                    .ledgerFont(.numeralM)
                    .foregroundStyle(isLive ? LedgerColor.ink : LedgerColor.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LedgerSpacing.s) {
                StepButton(icon: .minus, action: onDecrement)
                StepButton(icon: .plus, action: onIncrement)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? value)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else {
                return
            }
            switch direction {
            case .increment: onIncrement?()
            case .decrement: onDecrement?()
            @unknown default: break
            }
        }
        .disabled(onDecrement == nil && onIncrement == nil)
    }
}

/// "−" or "+": a round outlined button, 44 pt across at the default text size and growing with its icon.
/// Without an action, or in a disabled field, it is drawn faint and does nothing.
private struct StepButton: View {
    let icon: LedgerIcon
    let action: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isOn = isEnabled && action != nil
        Button {
            action?()
        } label: {
            LedgerIconView(icon, sizedAs: .subheading)
                .foregroundStyle(isOn ? LedgerColor.inkSecondary : LedgerColor.inkFaint)
                .padding(LedgerSpacing.s)
                .ledgerHitTarget()
                .overlay(Circle().strokeBorder(
                    isOn ? LedgerColor.hairlineStrong : LedgerColor.hairline,
                    lineWidth: LedgerHairline.width
                ))
        }
        .buttonStyle(LedgerPressStyle())
        .disabled(action == nil)
    }
}

/// Every state, for the preview, the snapshot tests and the gallery: both steps on, a value at its lowest
/// (no "−") and at its highest (no "+"), a long label and value, and a disabled field.
struct StepperFieldGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            StepperField("Sets", value: "5", onDecrement: {}, onIncrement: {})
            HairlineRule()
            StepperField("Rest", value: "0:30", spokenValue: "30 seconds", onDecrement: nil, onIncrement: {})
            HairlineRule()
            StepperField("Target RPE", value: "10", onDecrement: {}, onIncrement: nil)
            HairlineRule()
            StepperField("Start load for the first week", value: "1,022.5 lb", onDecrement: {}, onIncrement: {})
            HairlineRule()
            StepperField("Top of range", value: "12", onDecrement: {}, onIncrement: {})
                .disabled(true)
        }
    }
}
