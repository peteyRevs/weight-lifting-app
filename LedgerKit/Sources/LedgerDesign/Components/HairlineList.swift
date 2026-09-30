import SwiftUI

/// Rows stacked flush, each under its own top rule, with a closing rule at the bottom. v2 draws
/// lists as hairlines, not cards ("RECENT", "REMAINING", the swap sheet, the set rows): every
/// row has `border-top: 1px`, and the list ends with one more rule.
public struct HairlineList<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
            HairlineRule()
        }
    }
}

/// A full-width one-point rule in `LedgerColor.hairline`, or another rule colour.
public struct HairlineRule: View {
    private let color: Color

    public init(_ color: Color = LedgerColor.hairline) {
        self.color = color
    }

    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: LedgerHairline.width)
            .accessibilityHidden(true)
    }
}

/// A list with each kind of row, for the preview, the snapshot tests and the gallery.
struct HairlineListGallery: View {
    var body: some View {
        HairlineList {
            HairlineRow("Barbell Bench Press") {
                Text("5 × 5 @ 185").ledgerFont(.numeralS).foregroundStyle(LedgerColor.inkSecondary)
            }
            HairlineRow("Lower A — Squat focus", detail: "Mon · 58 min · 24,180 lb") {} accessory: {
                LedgerIconView(.chevron, sizedAs: .body).foregroundStyle(LedgerColor.inkMuted)
            }
            HairlineRow("Dumbbell Bench Press", detail: "Similar pattern · 2 × 70 lb") {} accessory: {
                Text("Use").ledgerFont(.caption).foregroundStyle(LedgerColor.accentText)
            }
            HairlineRow("Seated Cable Row")
        }
    }
}
