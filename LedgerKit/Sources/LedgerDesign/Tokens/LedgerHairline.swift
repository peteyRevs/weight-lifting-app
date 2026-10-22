import CoreGraphics

/// Rule and border weights (docs/product-spec.md §8.6). v2 draws every hairline and border at
/// 1 CSS px, which is 1 pt, not one device pixel. Colours are `LedgerColor.hairline` / `.hairlineStrong`.
public nonisolated enum LedgerHairline {
    public static let width: CGFloat = 1
    /// v2 Exercise history's chart: each week's bar is a 2 px rule with round ends (F12 S2).
    public static let bar: CGFloat = 2
}
