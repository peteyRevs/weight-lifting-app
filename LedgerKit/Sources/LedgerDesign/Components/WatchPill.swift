import SwiftUI

/// The watch's pill (LedgerWatch): full width, at least 44 pt tall, a 700 label that wraps when long. `.filled` is the
/// screen's one orange action ("Start", "Done set", "Skip"); `.outlined` is drawn in a 22 % rule ("+30s", "End
/// workout", "Done"). Without an action the pill is a line, not a button: the outlined "Next: Friday · UB" a rest day
/// shows, whose words are muted. Disabled, a pill turns grey; with the wrist down (Always-On) its orange dims.
///
/// `title` is shown as given and is what VoiceOver reads; features pass copy from their catalog.
public struct WatchPill: View {
    public enum Style: Sendable {
        case filled, outlined
    }

    private let title: String
    private let style: Style
    private let action: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(_ title: String, style: Style = .filled, action: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(LedgerPressStyle())
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        Text(title)
            .ledgerFont(.watchButton)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled && action != nil ? LedgerColor.watchInk : LedgerColor.watchInkMuted)
            .padding(.horizontal, LedgerSpacing.l)
            .padding(.vertical, LedgerSpacing.m)
            .frame(maxWidth: .infinity, minHeight: LedgerHitTarget.minimum)
            .background { shape }
            .contentShape(.ledgerPill)
    }

    @ViewBuilder private var shape: some View {
        switch style {
        case .filled:
            Capsule.ledgerPill.fill(
                isEnabled ? WatchTokens.accent(isLuminanceReduced: isLuminanceReduced) : LedgerColor.watchHairline
            )
        case .outlined:
            Capsule.ledgerPill.strokeBorder(LedgerColor.watchOutline, lineWidth: LedgerHairline.width)
        }
    }
}

/// Every state: a filled and an outlined button, the rest screen's pair side by side, an outlined line with no
/// action and a disabled one, for the preview, the snapshot tests and the gallery.
struct WatchPillGallery: View {
    var body: some View {
        VStack(spacing: LedgerSpacing.s) {
            WatchPill("Start") {}
            WatchPill("End workout", style: .outlined) {}
            HStack(spacing: LedgerSpacing.s) {
                WatchPill("+30s", style: .outlined) {}
                WatchPill("Skip") {}
            }
            WatchPill("Next: Friday · UB", style: .outlined)
            WatchPill("Discard", style: .outlined) {}.disabled(true)
        }
    }
}
