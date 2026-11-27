import SwiftUI

/// The watch's own measures (spec §4.1, §4.3; R1 §5.5). The watch's type scale is `LedgerFont`'s `watch…` roles,
/// its palette `LedgerColor`'s `watch…` colours and its gaps `LedgerSpacing`'s steps; these are what the watch draws
/// that no shared token holds. Sizes are the prototype's pixels ÷ 1.5 (it is drawn at 1.5× a 46 mm display).
public nonisolated enum WatchTokens {
    /// A set dot on the set screen: 9 px.
    public static let setDot: CGFloat = 9 / 1.5
    /// The gap between two set dots: 4 px.
    public static let setDotGap: CGFloat = 4 / 1.5
    /// The orange dot before the heart rate: 8 px.
    public static let heartDot: CGFloat = 8 / 1.5
    /// The gaps between the heart dot, the number and "BPM": 7 px.
    public static let heartGap: CGFloat = 7 / 1.5
    /// The gap between the set screen's rows, and between the lines inside the rest ring: 3 px.
    public static let rowGap: CGFloat = 3 / 1.5
    /// The set screen's round reps buttons, "−" and "+": 44 px.
    public static let stepButton: CGFloat = 44 / 1.5
    /// The accent while the wrist is down (Always-On, `isLuminanceReduced`): orange at 60 % (R1 §5.5).
    public static let accentDimmed = LedgerColor.accent.opacity(0.6)

    /// The accent as the screen shows it now: dimmed while the wrist is down.
    public static func accent(isLuminanceReduced: Bool) -> Color {
        isLuminanceReduced ? accentDimmed : LedgerColor.accent
    }
}
