import XCTest

/// The issues the system's audit reports on the Program tab's root, the builder over the seed program at week 5,
/// that were measured and judged false positives (F11-S14-5; fix/tabs-audit). Each is named by the system's words
/// for it and by the element's type and label, as `TodayAuditExclusions` and `LibraryAuditExclusions` name theirs,
/// so another issue on the same element, or the same issue on another element, still fails. Each repeats a ruling
/// already made on Today or the Library for the same role; none is a token or a view of the builder's own.
///
/// Measured on the iPhone 17 (iOS 27.0), light, default text size, 26 issues: every element reported is a static
/// text but "Apply to later weeks" (a button).
enum ProgramAuditExclusions {
    /// The builder's texts set in the eyebrow role over the seed program: its headings, the week chips' second
    /// line, and the day rows' exercise chips (measured: each frame 10 pt high, the role's size and line).
    private static func isEyebrow(_ label: String) -> Bool {
        let patterns = [#"^BLOCK · \d+ WEEKS?$"#, #"^WEEK \d+( · DELOAD)?$"#, #"^\d+ DAYS?$"#, #"^\+\d+$"#]
        return ["MY PROGRAM", "TRAINING DAYS", "DELOAD"].contains(label) || seedChips.contains(label)
            || patterns.contains { label.range(of: $0, options: .regularExpression) != nil }
    }

    /// The exercise chips of the seed program's first two days, which the page shows at its top.
    private static let seedChips: Set = ["BENCH", "INCLINE", "CS ROW", "PULLDOWN", "SQUAT", "RDL", "LEG PRESS", "CALF"]

    /// The tab bar's own buttons, which a frame under the bar would also take in.
    private static let tabs: Set = ["Today", "Program", "Library", "History"]

    /// Whether `issue` on an element of `type`, `label` and `frame` is a measured false positive. `tabBar` is
    /// the tab bar's frame.
    static func isKnownFalsePositive(
        issue: String,
        type: XCUIElement.ElementType,
        label: String,
        frame: CGRect,
        tabBar: CGRect
    ) -> Bool {
        switch issue {
        case "Dynamic Type font sizes are partially unsupported":
            // As Today's F09-S5-2: `Eyebrow` is 10 pt on the Caption 2 curve, flat from Extra Small to Large, so
            // it does not shrink below the default size; it grows at every size above it
            // (`EyebrowDynamicTypeAdversarialTests`). 17 issues, all on texts of that role.
            type == .staticText && isEyebrow(label)
        case "Text clipped":
            // As Today's F09-S5-3 and 4: texts whose line is as tall as their size, the eyebrow (10 pt frames)
            // and the caption (the section's note, 12 pt; the pill's title, whose button is the 44 pt target).
            // Archivo's ascent and descent are 1.088 of the size, so a descender is drawn below the frame; the
            // whole screen shows each text whole ("4 days · 58 sets a week", "Apply to later weeks").
            (type == .staticText && (isEyebrow(label) || isWeekSummary(label)))
                || (type == .button && label == "Apply to later weeks")
        case "Contrast failed":
            // As Today's fourth and the Library's: the second day's row, resting under the floating tab bar while
            // the page is at its top (measured: its line and chips at y 796-833, inside the bar's 791-874, and
            // nothing above it). Scrolled to its end the page stands clear
            // (`ProgramAuditExclusionsAdversarial.test_lastControl_scrollsClearOfTheTabBar`).
            frame.intersects(tabBar) && !tabs.contains(label)
        default:
            false
        }
    }

    /// The training days' note: "4 days · 58 sets a week".
    private static func isWeekSummary(_ label: String) -> Bool {
        label.range(of: #"^\d+ days? · \d+ sets? a week$"#, options: .regularExpression) != nil
    }
}

/// fix/tabs-audit: that `ProgramAuditExclusions` excuses what was measured and nothing wider, and that what lies
/// under the tab bar can be brought clear of it. Nightly only.
final class ProgramAuditExclusionsAdversarial: XCTestCase {
    /// The tab bar as measured, a frame clear of it and one under it.
    private static let tabBar = CGRect(x: 0, y: 791, width: 402, height: 83)
    private static let clear = CGRect(x: 80, y: 600, width: 164, height: 15)
    private static let underBar = CGRect(x: 80, y: 796, width: 164, height: 15)

    /// One issue as the audit reports it, by the system's words, the element's type and label, and its frame.
    private struct Finding {
        let issue: String
        let type: XCUIElement.ElementType
        let label: String
        var frame = ProgramAuditExclusionsAdversarial.clear

        var isExcused: Bool {
            ProgramAuditExclusions.isKnownFalsePositive(
                issue: issue, type: type, label: label, frame: frame, tabBar: ProgramAuditExclusionsAdversarial.tabBar
            )
        }
    }

    func test_auditExclusions_excuseNothingWider() {
        let dynamic = "Dynamic Type font sizes are partially unsupported"
        let (text, button) = (XCUIElement.ElementType.staticText, XCUIElement.ElementType.button)
        let excused = [
            Finding(issue: dynamic, type: text, label: "WEEK 5"),
            Finding(issue: dynamic, type: text, label: "4 DAYS"),
            Finding(issue: dynamic, type: text, label: "+1"),
            Finding(issue: dynamic, type: text, label: "BLOCK · 8 WEEKS"),
            Finding(issue: "Text clipped", type: text, label: "TRAINING DAYS"),
            Finding(issue: "Text clipped", type: text, label: "4 days · 58 sets a week"),
            Finding(issue: "Text clipped", type: button, label: "Apply to later weeks"),
            Finding(
                issue: "Contrast failed",
                type: text,
                label: "4 exercises · 15 sets · ~38 min",
                frame: Self.underBar
            ),
            Finding(issue: "Contrast failed", type: text, label: "SQUAT", frame: Self.underBar)
        ]
        XCTAssertEqual(excused.filter { !$0.isExcused }.map(\.label), [], "not excused, and should be")
        let stillFailing = [
            Finding(issue: dynamic, type: text, label: "Upper / Lower"), // the title is no eyebrow
            Finding(issue: dynamic, type: text, label: "Tap to assign"),
            Finding(issue: dynamic, type: button, label: "4 DAYS"), // an eyebrow's words on a button
            Finding(issue: "Text clipped", type: text, label: "Copy week 4"), // not measured
            Finding(issue: "Text clipped", type: text, label: "Apply to later weeks"), // the button was, not a text
            Finding(issue: "Text clipped", type: text, label: "Shared by every week."),
            Finding(issue: "Contrast failed", type: text, label: "4 exercises · 15 sets · ~38 min"), // clear of the bar
            Finding(issue: "Contrast failed", type: button, label: "Program", frame: Self.underBar), // the bar's tab
            Finding(issue: "Contrast nearly passed", type: text, label: "SQUAT", frame: Self.underBar),
            Finding(issue: "Hit area is too small", type: text, label: "WEEK 5"),
            Finding(issue: "Dynamic Type font sizes are unsupported", type: text, label: "MY PROGRAM")
        ]
        XCTAssertEqual(stillFailing.filter(\.isExcused).map(\.label), [], "excused, and should not be")
    }

    /// The audit's "Contrast failed" under the floating tab bar is a false positive only if every row can be
    /// brought clear of the bar: scrolled to its end, the page's last control, "+ Add training day", stands whole
    /// above the bar, at the default size and at the largest.
    @MainActor
    func test_lastControl_scrollsClearOfTheTabBar() {
        for textSize in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication.fresh(["-LEDGER_UITEST_PROGRAM", "seed"])
            app.launchArguments += ["-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z"]
            if let textSize {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
            }
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            app.tabBars.buttons["Program"].tap()
            XCTAssertTrue(app.staticTexts["MY PROGRAM"].waitForExistence(timeout: 10))
            let addDay = app.buttons["+ Add training day"]
            var swipes = 0
            while swipes < 20, !addDay.isHittable || swipes < 3 {
                app.swipeUp(velocity: .fast)
                swipes += 1
            }
            app.swipeUp(velocity: .fast)
            let barFrame = app.tabBars.firstMatch.frame
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "scrolled to the end, \(textSize ?? "default size")"
            shot.lifetime = .keepAlways
            add(shot)
            XCTAssertTrue(addDay.exists)
            XCTAssertLessThanOrEqual(addDay.frame.maxY, barFrame.minY, "\(textSize ?? "default"): under the tab bar")
            app.terminate()
        }
    }
}
