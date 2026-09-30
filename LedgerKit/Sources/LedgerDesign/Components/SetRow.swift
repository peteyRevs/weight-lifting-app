import SwiftUI

public enum SetRowState: Sendable {
    /// Not logged and not selected.
    case pending
    /// The selected set: orange label, orange rule above, orange ring on the check.
    case active
    /// Logged: muted numerals and a tick in an orange disc.
    case done
}

/// One set in a live workout (v2 set rows): its label ("1", "D", "A1"), weight and reps as
/// numerals, and a round check. Tapping the row selects it; tapping the check logs the set or
/// un-logs it. The rule above it turns orange while it is the active set. Stack rows in a
/// ``HairlineList`` under a ``SetRowHeader``, with ``SetRowSteppers`` under the active row.
///
/// VoiceOver reads two buttons. The row reads its three strings with its state as the value
/// ("Current set", "Done"); a feature gives it a spoken label from outside,
/// `.accessibilityLabel("Set 2, 185 pounds, 5 reps")`, and that label stops at the row. The check
/// reads `checkLabel` ("Log set 2"), which a label from outside does not replace, and once done
/// it is selected and says "Done".
public struct SetRow: View {
    private let number: String
    private let weight: String
    private let reps: String
    private let state: SetRowState
    private let checkLabel: String
    private let onSelect: () -> Void
    private let onCheck: () -> Void

    public init(
        number: String,
        weight: String,
        reps: String,
        state: SetRowState,
        checkLabel: String,
        onSelect: @escaping () -> Void,
        onCheck: @escaping () -> Void
    ) {
        self.number = number
        self.weight = weight
        self.reps = reps
        self.state = state
        self.checkLabel = checkLabel
        self.onSelect = onSelect
        self.onCheck = onCheck
    }

    public var body: some View {
        VStack(spacing: 0) {
            HairlineRule(state == .active ? LedgerColor.accentLine : LedgerColor.hairline)
            HStack(spacing: LedgerSpacing.s) {
                Button(action: onSelect) {
                    SetColumns(
                        label: Text(number)
                            .ledgerFont(.caption)
                            .foregroundStyle(state == .active ? LedgerColor.accentText : LedgerColor.inkMuted),
                        weight: numeral(weight),
                        reps: numeral(reps)
                    )
                    .ledgerHitTarget()
                }
                .buttonStyle(LedgerPressStyle())
                .accessibilityValue(SetRowSpeech.state(state))
                Button(action: onCheck) { SetRowCheck(state: state) }
                    .buttonStyle(LedgerPressStyle())
                    .accessibilityLabel(checkLabel)
                    .accessibilityValue(state == .done ? SetRowSpeech.done : "")
                    .accessibilityAddTraits(state == .done ? .isSelected : [])
                    .accessibilityElement(children: .contain) // a label or value set on the row stops here
            }
            .padding(.vertical, LedgerSpacing.s)
        }
    }

    /// Done rows are muted, not the prototype's .28 `DIM`: the logged numbers still carry meaning
    /// and must reach AA. A value too long for its column at the largest text sizes shrinks rather
    /// than breaking mid-number.
    private func numeral(_ value: String) -> some View {
        Text(value)
            .ledgerFont(.numeralM)
            .foregroundStyle(state == .done ? LedgerColor.inkMuted : LedgerColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// What VoiceOver says for a set's state. English until LedgerDesign has a string catalog; the
/// keys are the English text.
private nonisolated enum SetRowSpeech {
    static var done: String {
        String(localized: "Done", bundle: .module, comment: "VoiceOver value of a logged set and of its check")
    }

    static var current: String {
        String(localized: "Current set", bundle: .module, comment: "VoiceOver value of the active set row")
    }

    static func state(_ state: SetRowState) -> String {
        switch state {
        case .pending: ""
        case .active: current
        case .done: done
        }
    }
}

/// The round check: a tick in an orange disc once done, an orange ring on the active set, a
/// muted ring otherwise. Each state's only mark meets WCAG's 3:1 for non-text on paper, card and
/// both dark grounds: the prototype's rings (.14 pending, .5 active) are raised, and the disc is
/// `accentText`, which is the accent itself in dark and `#B2390E` on paper, where the accent is
/// 2.65:1. The active ring is the screen's orange (the next thing to touch).
struct SetRowCheck: View {
    let state: SetRowState

    var body: some View {
        LedgerIconView(.check, sizedAs: .body)
            .foregroundStyle(LedgerColor.onAccent)
            .opacity(state == .done ? 1 : 0)
            .padding(LedgerSpacing.s)
            .background { disc }
            .ledgerHitTarget()
    }

    @ViewBuilder private var disc: some View {
        switch state {
        case .done: Circle().fill(LedgerColor.accentText)
        case .active: Circle().strokeBorder(LedgerColor.accentText, lineWidth: LedgerHairline.width)
        case .pending: Circle().strokeBorder(LedgerColor.inkMuted, lineWidth: LedgerHairline.width)
        }
    }
}

/// A logged set, the active set with its steppers, a pending set and a drop set, for the
/// preview, the snapshot tests and the gallery.
struct SetRowGallery: View {
    var body: some View {
        VStack(spacing: 0) {
            SetRowHeader(number: "#", weight: "lb", reps: "reps")
            HairlineList {
                SetRow(number: "1", weight: "185", reps: "5", state: .done, checkLabel: "Log set 1") {} onCheck: {}
                SetRow(number: "2", weight: "185", reps: "5", state: .active, checkLabel: "Log set 2") {} onCheck: {}
                SetRowSteppers(
                    weightStep: "5 lb",
                    repStep: "1 rep",
                    weight: "185 pounds",
                    reps: "5 reps",
                    onWeight: { _ in },
                    onReps: { _ in }
                )
                SetRow(
                    number: "3",
                    weight: "102.5",
                    reps: "12",
                    state: .pending,
                    checkLabel: "Log set 3"
                ) {} onCheck: {}
                SetRow(
                    number: "D",
                    weight: "155",
                    reps: "5",
                    state: .pending,
                    checkLabel: "Log drop set"
                ) {} onCheck: {}
            }
        }
    }
}
