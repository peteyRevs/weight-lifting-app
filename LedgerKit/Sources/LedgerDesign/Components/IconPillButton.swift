import SwiftUI

/// A round outlined button holding one icon (v2 swap button), 44 pt across at the default text
/// size and growing with its icon. `label` is what VoiceOver reads, since the icon has no text.
///
/// The icon is a ``LedgerIcon``, or one of Apple's symbols by name where the prototypes draw none
/// that a polyline can make (the Settings gear; product decision #19). A symbol is drawn as big as a
/// ``LedgerIcon`` in the same button, so the two kinds stand side by side.
public struct IconPillButton: View {
    /// What the button holds.
    private nonisolated enum Icon {
        case ledger(LedgerIcon)
        case symbol(String)
    }

    private let label: String
    private let icon: Icon
    private let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ label: String, icon: LedgerIcon, action: @escaping () -> Void) {
        self.label = label
        self.icon = .ledger(icon)
        self.action = action
    }

    /// A button holding the SF Symbol named `systemImage`.
    public init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label
        icon = .symbol(systemImage)
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            image
                .foregroundStyle(LedgerColor.inkSecondary)
                .padding(LedgerSpacing.m)
                .ledgerHitTarget()
                .overlay(Circle().strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width))
        }
        .buttonStyle(LedgerPressStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder private var image: some View {
        switch icon {
        case let .ledger(icon):
            LedgerIconView(icon, sizedAs: .button)
        case let .symbol(name):
            // The symbol fills the square a `LedgerIcon` is drawn in, whatever its own proportions.
            let side = LedgerFont.scaledSize(.button, dynamicTypeSize: dynamicTypeSize)
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
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

/// A round button holding one of Apple's symbols, beside one holding a ``LedgerIcon``, for the preview
/// and the snapshot tests.
struct IconPillButtonSymbolGallery: View {
    var body: some View {
        HStack(spacing: LedgerSpacing.m) {
            IconPillButton("Settings", systemImage: "gearshape") {}
            IconPillButton("Search", systemImage: "magnifyingglass") {}
            IconPillButton("Swap exercise", icon: .swap) {}
        }
    }
}
