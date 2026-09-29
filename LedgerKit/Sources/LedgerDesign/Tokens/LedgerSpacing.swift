import CoreGraphics

/// Spacing scale in points (docs/product-spec.md §8.6). Features never write a numeric padding or
/// stack spacing (`ledger_raw_spacing`); they pick a step from here.
public nonisolated enum LedgerSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    /// Side inset of a phone screen (v2 Today: `padding: 72px 26px`).
    public static let screen: CGFloat = 26
}
