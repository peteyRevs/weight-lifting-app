import SwiftUI

/// A choice of one among a few short options, side by side on one pill-shaped track (Settings' units, "LB" and
/// "KG"; the prototype's unit switch): the chosen option filled with ink, the others in muted ink on the track.
/// No orange: like `LedgerToggleStyle`, it is a form control, and the accent is kept for a screen's one thing.
///
/// String-only, as `FilterChipRow` is: the caller says, of each of its own options, its title, the name VoiceOver
/// reads for it ("pounds" for "LB") and whether it is the chosen one, and is handed the option a tap chose.
///
/// To VoiceOver it is a group named by `label` ("Units"), holding one button per option, the chosen one selected,
/// each with `hint` when one is given (the row's line under its title, "Applies to every log and chart").
/// Each option is a target of at least 44 × 44 pt, and its title keeps one line at every text size: the control
/// grows wider, never taller than its text.
public struct SegmentedChoice<Option: Identifiable>: View {
    private let label: String
    private let hint: String?
    private let options: [Option]
    private let title: (Option) -> String
    private let spokenLabel: (Option) -> String
    private let isSelected: (Option) -> Bool
    private let onSelect: (Option) -> Void

    public init(
        _ label: String,
        hint: String? = nil,
        options: [Option],
        title: @escaping (Option) -> String,
        spokenLabel: @escaping (Option) -> String,
        isSelected: @escaping (Option) -> Bool,
        onSelect: @escaping (Option) -> Void
    ) {
        self.label = label
        self.hint = hint
        self.options = options
        self.title = title
        self.spokenLabel = spokenLabel
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                SegmentedChoiceOption(
                    title: title(option),
                    spokenLabel: spokenLabel(option),
                    hint: hint,
                    isSelected: isSelected(option)
                ) { onSelect(option) }
            }
        }
        .padding(.horizontal, SegmentedChoiceOption.inset)
        .background(Capsule.ledgerPill.fill(LedgerColor.hairline))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// One option: its title on a pill of ink when chosen, on the bare track when not.
private struct SegmentedChoiceOption: View {
    /// Between the track's edge and an option's pill; the prototype's 3 px.
    static let inset: CGFloat = 3
    /// The prototype's 50 px option.
    static let minimumWidth: CGFloat = 50

    let title: String
    let spokenLabel: String
    let hint: String?
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .ledgerFont(.caption)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, LedgerSpacing.l)
                .padding(.vertical, LedgerSpacing.s)
                .frame(minWidth: Self.minimumWidth)
                .ledgerHitTarget()
                .background {
                    if isSelected {
                        Capsule.ledgerPill.fill(isEnabled ? LedgerColor.ink : LedgerColor.inkFaint)
                            .padding(.vertical, Self.inset)
                    }
                }
        }
        .buttonStyle(LedgerPressStyle())
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        guard isEnabled else {
            return isSelected ? LedgerColor.ground : LedgerColor.inkFaint
        }
        return isSelected ? LedgerColor.ground : LedgerColor.inkMuted
    }
}

/// Two options with the first chosen, then the second, and a choice of three, for the preview, the snapshot
/// tests and the gallery.
struct SegmentedChoiceGallery: View {
    private struct Option: Identifiable {
        let id: Int
        let title: String
        let spoken: String
    }

    private static let units = [
        Option(id: 0, title: "LB", spoken: "pounds"), Option(id: 1, title: "KG", spoken: "kilograms")
    ]
    private static let sides = ["Left", "Both", "Right"].enumerated()
        .map { Option(id: $0.offset, title: $0.element, spoken: $0.element) }

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            choice("Units", Self.units, chosen: 0)
            choice("Units", Self.units, chosen: 1)
            choice("Side", Self.sides, chosen: 1)
        }
    }

    private func choice(_ label: String, _ options: [Option], chosen: Int) -> some View {
        SegmentedChoice(
            label,
            options: options,
            title: \.title,
            spokenLabel: \.spoken,
            isSelected: { $0.id == chosen },
            onSelect: { _ in }
        )
    }
}
