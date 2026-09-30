import SwiftUI

/// A small pill for secondary actions (v2): `.outline` ("Finish", "Repeat", a filter), `.filled`
/// with ink (the selected filter), or `.ghost`, text only ("Cancel", "Skip setup", "+ Add set").
/// `.filled` means selected, so VoiceOver hears it as selected too. The pill is drawn at its text
/// size; the tappable area is at least 44 × 44 pt around it.
public struct PillButton: View {
    public nonisolated enum Style: Sendable {
        case outline, filled, ghost
    }

    private let title: String
    private let style: Style
    private let action: () -> Void

    public init(_ title: String, style: Style = .outline, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .ledgerFont(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
                .padding(.horizontal, style == .ghost ? 0 : LedgerSpacing.m)
                .padding(.vertical, LedgerSpacing.s)
                .background { pill }
                .ledgerHitTarget()
        }
        .buttonStyle(LedgerPressStyle())
        .accessibilityAddTraits(style == .filled ? .isSelected : [])
    }

    private var foreground: Color {
        switch style {
        case .outline: LedgerColor.ink
        case .filled: LedgerColor.ground
        case .ghost: LedgerColor.inkMuted // the prototype's .32–.40 ink is below AA
        }
    }

    @ViewBuilder private var pill: some View {
        switch style {
        case .outline: Capsule.ledgerPill.strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
        case .filled: Capsule.ledgerPill.fill(LedgerColor.ink)
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
