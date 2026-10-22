import XCTest

/// F12 S1 adversarial round 1 (G2): the system's accessibility audit on the Library tab, in the running app over a
/// fresh database (the bundled catalog, no history), at the default text size and at two accessibility sizes.
/// Each issue is kept with the element's type, label and frame, and a picture of the element, so a finding can be
/// looked at. `LibraryAuditExclusions` holds the issues measured and judged false positives (F12-S1-2); anything
/// else fails. Nightly only.
final class LibraryAuditAdversarial: XCTestCase {
    private static let sizes: [String?] = [
        nil, "UICTContentSizeCategoryAccessibilityL", "UICTContentSizeCategoryAccessibilityXXXL"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// The search field's "Text clipped" was F12-S1-1 (an edited query lost its tails, fixed in `d5704eb`); on the
    /// empty field it is measured and excluded (F12-S1-5).
    @MainActor
    func test_libraryRoot_passesTheAudit_butForItsMeasuredFalsePositives() throws {
        var issues: [String] = []
        for textSize in Self.sizes {
            let app = launchLibrary(textSize: textSize)
            issues += try audit(app, state: textSize ?? "default size")
            app.terminate()
        }
        XCTAssertEqual(issues, [])
    }

    /// F12-S1-5 (G1 round 3, sanctioned addition; tightened in round 4, review M1): the audit's "Text clipped" on
    /// the empty search field, measured. At each size the field's picture is read row by row and column by column
    /// (`PlaceholderInk.faults`): the placeholder's ink lies between the pill's two strokes, clear of both; it is
    /// as tall for its width as a whole line of it (a clip to the field's text box, or a sliver, is not); and it
    /// ends short of the trailing padding (a placeholder cut short with "…" runs into it). The guards are proved
    /// by `test_placeholderGuards_failOnAClippedAndOnATruncatedPicture`.
    @MainActor
    func test_searchPlaceholder_isDrawnWholeInsideTheField() throws {
        for textSize in Self.sizes {
            let app = launchLibrary(textSize: textSize)
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            let shot = field.screenshot()
            attach(shot, named: "search field, \(textSize ?? "default size")")
            let ink = try XCTUnwrap(PlaceholderInk(shot.image), "the picture was not read")
            // The text drawn: the field's placeholder, which is not its spoken label.
            let drawn = field.placeholderValue ?? ""
            XCTAssertEqual(ink.faults(of: drawn), [], "\(textSize ?? "default size"), \(drawn), \(field.frame): \(ink)")
            app.terminate()
        }
    }

    /// Review M1 (c): the same guards on the real picture at Accessibility XXXL, doctored twice: its placeholder's
    /// lower third painted over with the pill's ground, as a clip to the field's text box would leave it; and a
    /// column of ink drawn into the trailing padding, where a placeholder cut short with "…" ends. Each must be
    /// found, and the undoctored picture must pass.
    @MainActor
    func test_placeholderGuards_failOnAClippedAndOnATruncatedPicture() throws {
        let app = launchLibrary(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let ink = try XCTUnwrap(PlaceholderInk(field.screenshot().image), "the picture was not read")
        let drawn = field.placeholderValue ?? ""
        XCTAssertEqual(drawn, "Search", "at Accessibility XXXL the whole placeholder does not fit")
        XCTAssertEqual(ink.faults(of: drawn), [], "control: the real picture passes: \(ink)")
        let clipped = try XCTUnwrap(PlaceholderInk(ink.clippingTheTextsLowerThird()))
        let truncated = try XCTUnwrap(PlaceholderInk(ink.inkingTheTrailingPadding()))
        let found = (clipped: clipped.faults(of: drawn), truncated: truncated.faults(of: drawn))
        let report = XCTAttachment(string: "clipped: \(found.clipped)\ntruncated: \(found.truncated)")
        report.name = "the guards on the doctored pictures"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertTrue(found.clipped.contains { $0.hasPrefix("too short") }, "a clip passes: \(clipped)")
        XCTAssertTrue(found.truncated.contains { $0.hasPrefix("into the trailing padding") }, "\(truncated)")
        app.terminate()
    }

    /// The audit's "Contrast failed" on the rows under the floating tab bar is the bar's glass measured over them
    /// while the page rests at its top. That is a false positive only if every row can be brought clear of the
    /// bar: scrolled to its end, the last row stands whole above it, at the default size and at the largest. A
    /// chip shortens the list so a few swipes reach the end (the whole catalog is some 16,000 pt long).
    @MainActor
    func test_lastRow_scrollsClearOfTheTabBar() {
        for textSize in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launchLibrary(textSize: textSize)
            // The bodyweight chip leaves a list a few screens long, whose end a few swipes reach.
            app.buttons["Equipment: Bodyweight"].tap()
            XCTAssertTrue(app.buttons["Equipment: Bodyweight"].isSelected)
            let page = app.scrollViews.firstMatch
            let last = page.buttons.allElementsBoundByIndex.last { $0.frame.height > 0 }
            // Swipes past the moment the last row comes on screen, so the page is at its end.
            var swipes = 0
            while swipes < 30, let last, !last.isHittable || swipes < 4 {
                page.swipeUp(velocity: .fast)
                swipes += 1
            }
            for _ in 0 ..< 2 {
                page.swipeUp(velocity: .fast)
            }
            let bar = app.tabBars.firstMatch.frame
            attach(app.screenshot(), named: "scrolled to the end, \(textSize ?? "default size")")
            XCTAssertNotNil(last)
            if let last {
                XCTAssertLessThanOrEqual(last.frame.maxY, bar.minY, "\(last.label): under the tab bar")
            }
            app.terminate()
        }
    }
}

/// The issues the system's audit reports on the Library at rest that were measured and judged false positives
/// (F12-S1-2, test-findings). Each is named by the system's words for it and by the element, as
/// `TodayAuditExclusions` names Today's, so another issue on the same element, or the same issue elsewhere, still
/// fails.
enum LibraryAuditExclusions {
    /// The Library's eyebrows.
    private static let eyebrows: Set = ["RECENTLY LOGGED", "ALL EXERCISES"]

    /// The tab bar's own buttons, which a frame under the bar would also take in.
    private static let tabs: Set = ["Today", "Program", "Library", "History"]

    /// Whether `issue` on `element` is a measured false positive. Round 4 (review M1, m1): the search field is
    /// matched as an empty text field, never by its label, which stays the placeholder while a query is typed;
    /// and what lies under the tab bar is excluded only when it is not one of the bar's own buttons.
    @MainActor
    static func isKnownFalsePositive(issue: String, element: XCUIElement, tabBar: CGRect) -> Bool {
        let (label, frame) = (element.label, element.frame)
        return switch issue {
        case "Dynamic Type font sizes are partially unsupported":
            // As Today's F09-S5-2: `Eyebrow` is 10 pt on the Caption 2 curve, flat from Extra Small to Large, so
            // it does not shrink below its default size; it grows at every size above (measured: 10 pt tall at
            // the default size, 22.3 at Accessibility L, 74 on two lines at Accessibility XXXL).
            eyebrows.contains(label)
        case "Text clipped":
            // As Today's F09-S5-4: the eyebrow's frame is its line, as tall as its size, and Archivo's ascent and
            // descent are 1.088 of it; its capitals have no tail, and the pictures at every size show it whole.
            // F12-S1-5 (G1 rounds 3 and 4): the empty search field, whose placeholder ("Search 224 exercises",
            // or "Search" where it does not fit; no descender) is drawn whole between the pill's strokes and short
            // of its trailing padding at the default size, Accessibility L and XXXL
            // (`test_searchPlaceholder_isDrawnWholeInsideTheField`, whose guards are shown to fail on a clipped
            // and a truncated picture; the reported frames are the field's, 350 x 44, 51 and 72 pt). An edited
            // query's tails were F12-S1-1, fixed by the field's line (`d5704eb`); an edited field is not excluded.
            eyebrows.contains(label) || isEmptySearchField(element)
        case "Contrast failed":
            // As Today's fourth: a row of the page resting under the floating tab bar while the page is at its top
            // (measured: every element reported lies inside the bar's frame, y 791-874, and none above it).
            // Scrolled to its end the page stands clear (`test_lastRow_scrollsClearOfTheTabBar`). By frame and by
            // label, as Today's: the bar's own buttons are never excluded, so a tab whose contrast really fails
            // still fails (review m1).
            frame.intersects(tabBar) && !tabs.contains(label)
        default:
            false
        }
    }

    /// A text field with nothing typed: its value is empty or is its placeholder, as XCUITest reads an empty field.
    @MainActor
    private static func isEmptySearchField(_ element: XCUIElement) -> Bool {
        let value = element.value as? String ?? ""
        return element.elementType == .textField && (value.isEmpty || value == element.placeholderValue)
    }
}

private extension LibraryAuditAdversarial {
    @MainActor
    func launchLibrary(textSize: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z"]
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.title"].waitForExistence(timeout: 10))
        return app
    }

    /// The audit of what is on screen, less `LibraryAuditExclusions`, one line per issue with the element's type,
    /// label and frame. The screen, each element and the excluded lines are kept with the result.
    @MainActor
    func audit(_ app: XCUIApplication, state: String) throws -> [String] {
        attach(app.screenshot(), named: "\(state): screen")
        var issues: [String] = []
        var excluded: [String] = []
        var elements: [(String, XCUIElement)] = []
        let tabBar = app.tabBars.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            var line = "\(state): \(issue.compactDescription)"
            var isKnown = false
            if let element = issue.element {
                let frame = element.frame
                let box = "x \(Int(frame.minX)) y \(Int(frame.minY)) w \(Int(frame.width)) h \(Int(frame.height))"
                line += " [\(element.elementType.rawValue) \"\(element.label)\" \(box)]"
                elements.append(("\(state): \(issue.compactDescription): \(element.label)", element))
                isKnown = LibraryAuditExclusions.isKnownFalsePositive(
                    issue: issue.compactDescription, element: element, tabBar: tabBar
                )
            } else {
                line += " [no element]"
            }
            if isKnown {
                excluded.append(line)
            } else {
                issues.append(line)
            }
            return true
        }
        let list = XCTAttachment(string: excluded.joined(separator: "\n"))
        list.name = "\(state): excluded"
        list.lifetime = .keepAlways
        add(list)
        for (name, element) in elements where element.exists {
            attach(element.screenshot(), named: name)
        }
        return issues
    }

    @MainActor
    func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
