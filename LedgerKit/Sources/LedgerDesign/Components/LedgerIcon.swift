import SwiftUI

/// The prototypes' stroked icons (docs/product-spec.md §8.7): polylines on a 24-point grid with
/// round caps and joins, at the stroke width the prototype draws them with. Draw one with
/// ``LedgerIconView``.
public nonisolated enum LedgerIcon: CaseIterable, Sendable {
    /// `M5 12h13m-5-6l6 6-6 6`, on "Start workout".
    case arrow
    /// `M5 12.5l4.5 4.5L19 7`, the set-row tick.
    case check
    /// `M9 5l7 7-7 7`, a row's disclosure chevron.
    case chevron
    /// `M4 8h13l-3.5-3.5M20 16H7l3.5 3.5`, the swap-exercise button.
    case swap
    /// The steppers' "−" and "+", drawn to match the prototype's Archivo 300 glyphs.
    case minus, plus

    /// Bold Text strokes icons this much heavier, as it steps text up one weight.
    static let boldTextStrokeScale: CGFloat = 1.3

    /// The stroke width on the 24-point grid (the SVG's `stroke-width`).
    var strokeWidth: CGFloat {
        switch self {
        case .arrow: 1.9
        case .check: 2.4
        case .chevron: 1.8
        case .swap: 1.6
        case .minus, .plus: 1.5
        }
    }

    /// Whether the icon is drawn mirrored in a right-to-left layout. Apple's guidance (Human Interface
    /// Guidelines, "Right to left") flips an icon that shows a direction of reading or of movement and never
    /// a check mark: the arrow and the chevron point forward, and so does the upper arrow of the swap pair.
    /// The check mark stays as drawn; the steppers' signs are their own mirror images.
    var mirrorsRightToLeft: Bool {
        switch self {
        case .arrow, .chevron, .swap: true
        case .check, .minus, .plus: false
        }
    }

    /// The strokes as polylines on the 24-point grid.
    var strokes: [[CGPoint]] {
        switch self {
        case .arrow: [[point(5, 12), point(18, 12)], [point(13, 6), point(19, 12), point(13, 18)]]
        case .check: [[point(5, 12.5), point(9.5, 17), point(19, 7)]]
        case .chevron: [[point(9, 5), point(16, 12), point(9, 19)]]
        case .swap: [[point(4, 8), point(17, 8), point(13.5, 4.5)], [point(20, 16), point(7, 16), point(10.5, 19.5)]]
        case .minus: [[point(6, 12), point(18, 12)]]
        case .plus: [[point(6, 12), point(18, 12)], [point(12, 6), point(12, 18)]]
        }
    }

    private func point(_ across: CGFloat, _ down: CGFloat) -> CGPoint {
        CGPoint(x: across, y: down)
    }
}

/// A ``LedgerIcon`` as big as a type role's text, so it scales with Dynamic Type beside that text,
/// and stroked heavier under Bold Text. Colour it with `foregroundStyle`. It is decorative:
/// VoiceOver skips it, and the control that holds it carries the label.
public struct LedgerIconView: View {
    private let icon: LedgerIcon
    private let role: LedgerFont.Role
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init(_ icon: LedgerIcon, sizedAs role: LedgerFont.Role) {
        self.icon = icon
        self.role = role
    }

    public var body: some View {
        let side = LedgerFont.scaledSize(role, dynamicTypeSize: dynamicTypeSize)
        let weight = legibilityWeight == .bold ? LedgerIcon.boldTextStrokeScale : 1
        LedgerIconShape(icon: icon, lineWidth: icon.strokeWidth * weight)
            .frame(width: side, height: side)
            // A shape turns round in a right-to-left layout, which drew the check mark backwards there. So the
            // shape is always drawn as on its grid, and this, the one place, flips the icons that point along
            // the reading direction. (`Shape.layoutDirectionBehavior = .fixed` did not stop the mirroring:
            // measured 2026-10-12, 204 pixels of a 32-point check mark still moved.)
            .environment(\.layoutDirection, .leftToRight)
            .flipsForRightToLeftLayoutDirection(icon.mirrorsRightToLeft)
            .accessibilityHidden(true)
    }
}

/// The icon's strokes, outlined so the shape fills with the foreground style.
nonisolated struct LedgerIconShape: Shape {
    let icon: LedgerIcon
    /// On the 24-point grid.
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var path = Path()
        for stroke in icon.strokes {
            path.addLines(stroke.map { CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale) })
        }
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
    }
}
