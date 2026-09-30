import SwiftUI

public extension View {
    /// Grows the view to at least 44 × 44 pt, the iOS minimum hit target (engineering-standards §7),
    /// and makes all of that area tappable, without changing what it draws. Components apply it
    /// inside their button's label, so the button (and its accessibility frame) is the full target.
    func ledgerHitTarget() -> some View {
        frame(minWidth: LedgerHitTarget.minimum, minHeight: LedgerHitTarget.minimum)
            .contentShape(Rectangle())
    }
}

public extension Shape where Self == Capsule {
    /// The pill every v2 control is drawn in: CSS `border-radius: 999px`, whose ends are circular.
    /// SwiftUI's default capsule has continuous corners (iOS 26), a different outline.
    static var ledgerPill: Capsule {
        Capsule(style: .circular)
    }
}

nonisolated enum LedgerHitTarget {
    /// HIG: 44 × 44 pt on iOS.
    static let minimum: CGFloat = 44
}

extension View {
    /// A component gallery as a phone screen shows it: the screen inset, on the ground. Previews and
    /// the snapshot tests use it (the tests at the iPhone 17 width).
    func ledgerGalleryPage() -> some View {
        padding(LedgerSpacing.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LedgerColor.ground)
    }
}

/// The components' button style: the label draws its own idle and disabled looks, and dims
/// while pressed.
struct LedgerPressStyle: ButtonStyle {
    /// The label's opacity while a finger is down.
    static let pressedOpacity = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}
