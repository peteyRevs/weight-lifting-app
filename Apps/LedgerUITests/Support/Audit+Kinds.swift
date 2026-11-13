import XCTest

/// The kinds of false positive F15's audits measured (S2a; the implementation notes, F15-S2-3 to 9). Each kind is
/// the measured precedent of F08, F09 or F12 applied to F15's screens, and each screen names exactly the screens
/// and elements it excuses: the same issue on another element, or another issue on the same one, still fails
/// (`AuditExclusionsTests`).
extension ScreenExclusion {
    /// How far above its top element a pinned part begins: its 16 pt padding and the rule over it, measured on the
    /// rest panel (17 pt above `workout.rest.status`) and on the sheets' bottom buttons (11 pt above).
    static let pinnedMargin: CGFloat = 24

    /// The tab bar's own buttons, which a frame under the bar also takes in: never excused.
    private static let tabs: Set = ["Today", "Program", "Library", "History"]

    /// F15-S2-3, as Today's F09-S5-2: an eyebrow (`Eyebrow`, 10 pt on the Caption 2 curve, flat from Extra Small
    /// to Large) does not shrink below the default size, and grows at every size above it (10 pt tall at the
    /// default size, 37 pt at Accessibility XXXL in these runs).
    static func eyebrows(_ labels: Set<String>, on screens: Set<String>) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-3", issue: "Dynamic Type partially unsupported on an eyebrow") {
            $0.summary == "Dynamic Type font sizes are partially unsupported" && $0.elementType == .staticText
                && screens.contains($0.screen) && labels.contains($0.label)
        }
    }

    /// F15-S2-4, as F09-S5-3 and 4 (F06's native line height, Pete 2026-09-29): a text in a role whose line is as
    /// tall as its size or 1.08 of it (caption, eyebrow, button, heading, title), whose frame is that line while
    /// Archivo's ascent and descent are 1.088 of the size. The pictures of each, at the default size and at
    /// Accessibility XXXL, show every glyph whole.
    static func shortLines(_ labels: Set<String>, on screens: Set<String>) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-4", issue: "Text clipped on a role's native line") {
            $0.summary == "Text clipped" && [.staticText, .button, .textField].contains($0.elementType)
                && screens.contains($0.screen) && labels.contains($0.label)
        }
    }

    /// F15-S2-5, as Today's fourth and F12-S1-2: what rests under the floating tab bar while the page is at its
    /// top is measured through the bar's glass. Each screen it is excused on is shown to scroll clear of the bar
    /// (`ScreenAudit.expectScrollsClearOfTheTabBar`). The bar's own buttons are never excused.
    static func underTheTabBar(on screens: Set<String>) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-5", issue: "Contrast failed under the tab bar") {
            $0.summary == "Contrast failed" && screens.contains($0.screen) && !$0.tabBar.isNull
                && $0.frame.intersects($0.tabBar) && !tabs.contains($0.label)
        }
    }

    /// F15-S2-6, as onboarding's F8-S3-2 third: a line of the page that reaches under a pinned part (the rest panel,
    /// a sheet's bottom button) is measured against the part, not its own ground; in the pictures it is hidden.
    /// The page scrolls clear of the rest panel (`WorkoutRest.test_rest_atAnAccessibilitySize_thePageScrollsClear
    /// OfThePanel`). That a sheet's last row scrolls clear of its button is not proven by a UI test yet (S2a's
    /// notes list it for S2b's reachability pass).
    static func underThePinnedPart(on screens: Set<String>) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-6", issue: "Contrast failed under a pinned part") {
            $0.summary == "Contrast failed" && [.staticText, .button].contains($0.elementType)
                && screens.contains($0.screen) && !$0.pinned.isNull && $0.frame.maxY > $0.pinned.minY
        }
    }

    /// F15-S2-7, as F09-S5-1 and onboarding's first: white on the accent, 3.10:1, which WCAG counts enough for
    /// the button role's 16 pt bold (large text, AA 3:1; `LedgerFont`'s `.button`).
    static func accentButtons(_ labels: Set<String>, on screens: Set<String>) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-7", issue: "Contrast nearly passed on the accent button") {
            $0.summary == "Contrast nearly passed" && $0.elementType == .button
                && screens.contains($0.screen) && labels.contains($0.label)
        }
    }
}
