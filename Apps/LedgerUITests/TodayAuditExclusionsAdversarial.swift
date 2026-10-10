import XCTest

/// F09 S5 adversarial round 2 (G2), criterion 19: the four false positives of the system's accessibility audit
/// on Today, and nothing else (testing-strategy §2.7). Each was measured in round 1 (the notes, "The audit: a
/// verdict on each issue"; findings F09-S5-1 to 4). An exclusion names the issue by the system's own words
/// for it and the element by its label, so that another issue on the same element, or the same issue on
/// another element, still fails: a button whose contrast really fails is "Contrast failed", not "nearly
/// passed", and is not excluded. Today has no identifiers but `today.title` (F15 adds them), so the label is
/// the narrowest name there is; no radar is named because none is filed: these are the audit's rules met by
/// the design's own choices, not a bug of the system's.
///
/// Used by `TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit` and by
/// `TodayAuditAdversarial`. The one thing a label cannot tell is a text that is really cut on one of the
/// labels below: that is `TodayViewsLayoutAdversarialTests`' and the snapshot references' to catch.
enum TodayAuditExclusions {
    /// The orange button's labels a UI test can reach. "Resume · 0:04" counts, so it is named by its start.
    private static func isOrangeButton(_ label: String) -> Bool {
        ["Set up program", "Start workout"].contains(label) || label.hasPrefix("Resume · ")
    }

    /// The eyebrows a UI test can reach.
    private static let eyebrows: Set = ["RECENT", "UP NEXT", "SCHEDULED REST"]

    /// The header's date: "Wednesday, September 16".
    private static func isHeaderDate(_ label: String) -> Bool {
        label.range(of: #"^[A-Z][a-z]+day, [A-Z][a-z]+ \d{1,2}$"#, options: .regularExpression) != nil
    }

    /// The texts set in a role whose line is as tall as its size (the caption, the eyebrow, the button) or
    /// 1.08 of it (the heading), on the states a UI test can reach.
    private static func isShortLineText(_ label: String) -> Bool {
        isOrangeButton(label) || isHeaderDate(label)
            || ["SCHEDULED REST", "No session today", "Lower A — Squat focus"].contains(label)
            || label.range(of: #"^Week \d of \d · ~\d+ min$"#, options: .regularExpression) != nil
    }

    /// The page's last two texts, which rest under the floating tab bar until the page is scrolled.
    private static let lastTexts: Set = ["RECENT", "No sessions yet. Your first workout lands here."]

    /// Whether the system's `issue` on the element labelled `label` at `frame` is one of the four measured
    /// false positives. `tabBar` is the tab bar's frame.
    static func isKnownFalsePositive(issue: String, label: String, frame: CGRect, tabBar: CGRect) -> Bool {
        switch issue {
        case "Contrast nearly passed":
            // F09-S5-1. The orange button: white (255, 255, 255) on the accent (255, 91, 34) measures 3.10:1
            // in the run's own pixels, light and dark. The label is 16 pt at weight 700, which WCAG 2.1 counts
            // as large text (bold from 14 pt), whose AA minimum is 3:1; `LedgerFont`'s `.button` says so. The
            // system does not report it at an accessibility text size. The margin of 0.10 is listed for Pete.
            isOrangeButton(label)
        case "Dynamic Type font sizes are partially unsupported":
            // F09-S5-2. The eyebrows: 10 pt on the system's Caption 2 curve, which is flat from Extra Small
            // to Large, so the text does not shrink below the default size and grows at every size above
            // it (10 pt up to Large, 22 pt tall at Accessibility Large in the run). Pinned by
            // `EyebrowDynamicTypeAdversarialTests`.
            eyebrows.contains(label)
        case "Text clipped":
            // F09-S5-3 (the orange button's label) and F09-S5-4 (the header's date, and the other texts in
            // the same roles). Nothing is cut on screen (round 1's pictures, at the default size and at
            // Accessibility Large). The text's frame is the role's line, 1.0 or 1.08 of its size, and
            // Archivo's ascent plus descent is 1.088 of it (0.878 + 0.210, read from the font file), so
            // descenders are drawn below the frame: F06's native line height (Pete, 2026-09-29).
            isShortLineText(label)
        case "Contrast failed":
            // The fourth: what lies under the floating tab bar while the page rests at its top. The system
            // measures the bar's glass over the text. Scrolled to its end the page stands clear of the bar
            // (`TodayAuditAdversarial.test_sessionDay_theLastLineScrollsClearOfTheTabBar`). By label and by
            // frame: the same text above the bar is not excluded.
            lastTexts.contains(label) && frame.intersects(tabBar)
        default:
            false
        }
    }
}
