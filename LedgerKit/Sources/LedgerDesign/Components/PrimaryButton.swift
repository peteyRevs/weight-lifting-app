import SwiftUI

/// The orange pill: the one accent-filled action on a screen (spec §8.4), full width and at least
/// 54 pt tall (v2 "Start workout": 16 px label, 19 px padding, optional arrow). Disabled, it turns
/// grey (v1 "Select exercises to add": ink .10 fill).
///
/// `title` is shown as given; features pass copy from their string catalog.
public struct PrimaryButton: View {
    /// Spec §8.6: "primary CTA height ≈ 54 px".
    static let minimumHeight: CGFloat = 54

    private let title: String
    private let icon: LedgerIcon?
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, icon: LedgerIcon? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: LedgerSpacing.s) {
                Text(title)
                    .ledgerFont(.button)
                    .multilineTextAlignment(.center)
                if let icon {
                    LedgerIconView(icon, sizedAs: .button)
                }
            }
            .foregroundStyle(isEnabled ? LedgerColor.onAccent : LedgerColor.inkMuted)
            .padding(.horizontal, LedgerSpacing.xl)
            .padding(.vertical, LedgerSpacing.m)
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
            .background(isEnabled ? LedgerColor.accent : LedgerColor.hairline, in: .ledgerPill)
            .contentShape(.ledgerPill)
        }
        .buttonStyle(LedgerPressStyle())
    }
}

/// Every state, for the preview, the snapshot tests and the gallery.
struct PrimaryButtonGallery: View {
    var body: some View {
        VStack(spacing: LedgerSpacing.xl) {
            PrimaryButton("Start workout", icon: .arrow) {}
            PrimaryButton("Resume workout · 12:48") {}
            PrimaryButton("Save workout") {}.disabled(true)
        }
    }
}
