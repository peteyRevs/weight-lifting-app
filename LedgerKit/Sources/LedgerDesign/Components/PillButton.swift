import SwiftUI

/// A small pill for secondary actions (v2): `.outline` ("Finish", "Repeat", a filter), `.filled`
/// with ink (the selected filter), or `.ghost`, text only ("Cancel", "Skip setup", "+ Add set").
/// `.filled` means selected, so VoiceOver hears it as selected too. The pill is drawn at its text
/// size; the tappable area is at least 44 × 44 pt around it.
///
/// A pill narrower than its target stands in the target's middle. Where it must line up with an
/// edge (a ghost "Back" over a title, whose word would otherwise start 9 pt inside the content's
/// edge), pass `flush`: the pill stands at that edge of its target, and the target grows the other
/// way.
///
/// `fillsWidth` makes it a row's second action beside or under a `PrimaryButton` (v2 rest card: "+30s"
/// beside "Skip rest"): the pill takes the width it is offered and the primary button's height and label
/// size, so the two read as a pair. Only the outline and the filled style have a pill to widen.
///
/// Disabled, it looks disabled: the ink is `inkFaint`, the outline `hairline`, and a filled pill
/// takes `PrimaryButton`'s disabled fill and label. (v2 draws no disabled pill; F08's "Back"
/// during a save was the first.)
public struct PillButton: View {
    public nonisolated enum Style: Sendable {
        case outline, filled, ghost
    }

    private let title: String
    private let style: Style
    private let flush: HorizontalEdge?
    private let fillsWidth: Bool
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        style: Style = .outline,
        flush: HorizontalEdge? = nil,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.flush = flush
        self.fillsWidth = fillsWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .ledgerFont(fillsWidth ? .button : .caption)
                .multilineTextAlignment(textAlignment)
                .foregroundStyle(foreground)
                .padding(.horizontal, style == .ghost ? 0 : LedgerSpacing.m)
                .padding(.vertical, LedgerSpacing.s)
                .frame(
                    maxWidth: fillsWidth ? .infinity : nil,
                    minHeight: fillsWidth ? PrimaryButton.minimumHeight : nil
                )
                .background { pill }
                .ledgerHitTarget(alignment: Alignment(horizontal: targetAlignment, vertical: .center))
        }
        .buttonStyle(LedgerPressStyle())
        .accessibilityAddTraits(style == .filled ? .isSelected : [])
    }

    /// Where the pill stands in a target wider than itself.
    private var targetAlignment: HorizontalAlignment {
        switch flush {
        case .leading: .leading
        case .trailing: .trailing
        case nil: .center
        }
    }

    /// A title that wraps follows the pill: from the edge it stands at, or centred.
    private var textAlignment: TextAlignment {
        switch flush {
        case .leading: .leading
        case .trailing: .trailing
        case nil: .center
        }
    }

    private var foreground: Color {
        guard isEnabled else {
            return style == .filled ? LedgerColor.inkMuted : LedgerColor.inkFaint
        }
        return switch style {
        case .outline: LedgerColor.ink
        case .filled: LedgerColor.ground
        case .ghost: LedgerColor.inkMuted // the prototype's .32–.40 ink is below AA
        }
    }

    @ViewBuilder private var pill: some View {
        switch style {
        case .outline:
            Capsule.ledgerPill.strokeBorder(
                isEnabled ? LedgerColor.hairlineStrong : LedgerColor.hairline,
                lineWidth: LedgerHairline.width
            )
        case .filled: Capsule.ledgerPill.fill(isEnabled ? LedgerColor.ink : LedgerColor.hairline)
        case .ghost: EmptyView()
        }
    }
}

/// Every style, for the preview, the snapshot tests and the gallery.
struct PillButtonGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            PillButton("Finish") {}
            PillButton("Chest", style: .filled) {}
            PillButton("Skip setup", style: .ghost) {}
            PillButton("Repeat last session's sets") {}
        }
    }
}

/// The states the styles' gallery leaves out, for the preview and the snapshot tests: each style
/// disabled under its enabled self, and a ghost pill flush with each edge of a rule, beside one
/// that is centred in its target; then a full-width pill beside a primary button, and one alone, disabled.
struct PillButtonStatesGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            HStack(spacing: LedgerSpacing.l) {
                PillButton("Finish") {}
                PillButton("Chest", style: .filled) {}
                PillButton("Skip setup", style: .ghost) {}
            }
            HStack(spacing: LedgerSpacing.l) {
                PillButton("Finish") {}
                PillButton("Chest", style: .filled) {}
                PillButton("Skip setup", style: .ghost) {}
            }
            .disabled(true)
            HairlineRule()
            HStack(spacing: 0) {
                PillButton("Back", style: .ghost, flush: .leading) {}
                Spacer(minLength: 0)
                PillButton("Back", style: .ghost) {}
                Spacer(minLength: 0)
                PillButton("Edit", style: .ghost, flush: .trailing) {}
            }
            HairlineRule()
            HStack(spacing: LedgerSpacing.m) {
                PillButton("+30s", fillsWidth: true) {}
                PrimaryButton("Skip rest") {}
            }
            PillButton("+30s", fillsWidth: true) {}
                .disabled(true)
        }
    }
}
