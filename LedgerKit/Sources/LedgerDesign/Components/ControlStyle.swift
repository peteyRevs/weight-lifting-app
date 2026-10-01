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
    /// HIG: 44 × 44 pt on iOS, and the default control size on watchOS (HIG, Accessibility › Mobility:
    /// "watchOS 44x44 pt", minimum 28 × 28).
    static let minimum: CGFloat = 44
}

nonisolated extension LedgerFont {
    /// The `minimumScaleFactor` for a line of `role` text set at `size` points that may shrink rather
    /// than truncate: at most to half, and never below the role's floor. For the watch roles that floor
    /// is 11 pt (F06 criterion 4), so no shrunk watch text is ever smaller.
    static func shrinkLimit(_ role: Role, size: CGFloat) -> CGFloat {
        min(1, max(0.5, role.spec.minimumSize / size))
    }
}

extension View {
    /// A component gallery as a phone screen shows it: the screen inset, on the ground. Previews and
    /// the snapshot tests use it (the tests at the iPhone 17 width).
    func ledgerGalleryPage() -> some View {
        padding(LedgerSpacing.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LedgerColor.ground)
    }

    /// A watch component gallery as a watch screen shows it: the prototype's 20 px (13 pt) inset, on
    /// black. The watch has one, dark, appearance.
    func ledgerWatchPage() -> some View {
        padding(LedgerSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LedgerColor.watchGround)
    }
}

/// The components' button style: the label dims while pressed. `PrimaryButton` draws its own
/// disabled look; the others have none (slice 2, decision 7).
struct LedgerPressStyle: ButtonStyle {
    /// The label's opacity while a finger is down.
    static let pressedOpacity = 0.6

    func makeBody(configuration: Configuration) -> some View {
        PressedLook(isPressed: configuration.isPressed, label: configuration.label)
    }
}

/// The pressed look, apart from the style: a `ButtonStyleConfiguration` cannot be made outside a
/// button, so previews and snapshot tests draw it with `ledgerDrawsPressed`.
private struct PressedLook<Label: View>: View {
    let isPressed: Bool
    let label: Label
    @Environment(\.ledgerDrawsPressed) private var drawsPressed

    var body: some View {
        label.opacity(isPressed || drawsPressed ? LedgerPressStyle.pressedOpacity : 1)
    }
}

/// `nonisolated`, so the key `@Entry` generates is not main-actor-isolated by this module's default.
nonisolated extension EnvironmentValues {
    /// Draws every Ledger button as pressed: for previews and snapshot tests only.
    @Entry var ledgerDrawsPressed: Bool = false
}
