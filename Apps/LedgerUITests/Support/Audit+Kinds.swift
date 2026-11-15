import XCTest

/// The kinds of false positive F15's audits measured (S2a; the implementation notes, F15-S2-3 to 9). Each kind is
/// the measured precedent of F08, F09 or F12 applied to F15's screens, and names exactly the screens and elements
/// it was measured on: the same issue on another element or screen, or another issue on the same element, still
/// fails (`AuditExclusionsTests`).
extension ScreenExclusion {
    /// The tab bar's own buttons, which a frame under the bar also takes in: never excused.
    private static let tabs: Set = ["Today", "Program", "Library", "History"]

    /// F15-S2-3, as Today's F09-S5-2: an eyebrow (`Eyebrow`, 10 pt on the Caption 2 curve, flat from Extra Small
    /// to Large) does not shrink below the default size, and grows at every size above it (10 pt tall at the
    /// default size, 37 pt at Accessibility XXXL in these runs).
    static func eyebrows(_ measured: [String: Set<String>]) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-3", issue: "Dynamic Type partially unsupported on an eyebrow") {
            $0.summary == "Dynamic Type font sizes are partially unsupported" && $0.elementType == .staticText
                && measured[$0.screen]?.contains($0.label) == true
        }
    }

    /// F15-S2-4, as F09-S5-3 and 4 (F06's native line height, Pete 2026-09-29): a text in a role whose line is as
    /// tall as its size or 1.08 of it (caption, eyebrow, button, heading, title), whose frame is that line while
    /// Archivo's ascent and descent are 1.088 of the size. The pictures of each, at the default size and at
    /// Accessibility XXXL, show every glyph whole.
    static func shortLines(_ measured: [String: Set<String>]) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-4", issue: "Text clipped on a role's native line") {
            $0.summary == "Text clipped" && [.staticText, .button, .textField].contains($0.elementType)
                && measured[$0.screen]?.contains($0.label) == true
        }
    }

    /// F15-S2-5, as Today's fourth and F12-S1-2: what rests under the floating tab bar while the page is at its
    /// top is measured through the bar's glass. Each screen it is excused on is shown to scroll clear of the bar
    /// (`ScreenAudit.expectScrollsClear`). A text or button of the page whose middle lies inside the bar's frame (every
    /// one the runs reported does): one that only grazes the bar is measured against its own ground and is not
    /// excused. The bar's own buttons, which lie wholly inside it, are never excused, nor is what is no text or button.
    static func underTheTabBar(on screens: Set<String>) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-5", issue: "Contrast failed under the tab bar") { issue in
            let middle = CGPoint(x: issue.frame.midX, y: issue.frame.midY)
            return issue.summary == "Contrast failed" && [.staticText, .button].contains(issue.elementType)
                && screens.contains(issue.screen) && !issue.tabBar.isNull && issue.tabBar.contains(middle)
                && !tabs.contains(issue.label) && !(issue.elementType == .button && issue.tabBar.contains(issue.frame))
        }
    }

    /// F15-S2-6, as onboarding's F8-S3-2 third: a line of the page that reaches under a pinned part (the rest panel,
    /// a sheet's bottom button) is measured against the part, not its own ground; in the pictures it is hidden.
    /// The part's top is measured (`PinnedPart`), and its own elements (its buttons, its texts) are never excused.
    /// The page scrolls clear of the rest panel (`WorkoutRest.test_rest_atAnAccessibilitySize_thePageScrollsClear
    /// OfThePanel`), and a sheet's list of its foot (`ScreenAudit.expectScrollsClear`, in the walks).
    static func underThePinnedPart(on screens: Set<String>) -> ScreenExclusion {
        ScreenExclusion(finding: "F15-S2-6", issue: "Contrast failed under a pinned part") {
            $0.summary == "Contrast failed" && [.staticText, .button].contains($0.elementType)
                && screens.contains($0.screen) && !$0.pinned.isNull && $0.frame.maxY > $0.pinned.minY
                && !$0.inPinnedPart
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
