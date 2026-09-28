import CoreGraphics

/// Corner radii in points (docs/product-spec.md §8.6).
public nonisolated enum LedgerRadius {
    /// Every v2 interactive control and the watch buttons; larger than any control, so fully round.
    public static let pill: CGFloat = 999
    /// The rest card.
    public static let card: CGFloat = 26
    /// The top corners of a bottom sheet.
    public static let sheet: CGFloat = 28
    /// CTAs and stat tiles in the light (v1) layouts.
    public static let row: CGFloat = 16
}
