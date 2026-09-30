import SwiftUI

/// A round outlined button holding one icon (v2 swap button), 44 pt across at the default text
/// size and growing with its icon. `label` is what VoiceOver reads, since the icon has no text.
public struct IconPillButton: View {
    private let label: String
    private let icon: LedgerIcon
    private let action: () -> Void

    public init(_ label: String, icon: LedgerIcon, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            LedgerIconView(icon, sizedAs: .button)
                .foregroundStyle(LedgerColor.inkSecondary)
                .padding(LedgerSpacing.m)
                .ledgerHitTarget()
                .overlay(Circle().strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width))
        }
        .buttonStyle(LedgerPressStyle())
        .accessibilityLabel(label)
    }
}

/// Every icon a round button uses, for the preview, the snapshot tests and the gallery.
struct IconPillButtonGallery: View {
    var body: some View {
        HStack(spacing: LedgerSpacing.m) {
            IconPillButton("Swap exercise", icon: .swap) {}
            IconPillButton("Next", icon: .arrow) {}
            IconPillButton("Add", icon: .plus) {}
        }
    }
}
