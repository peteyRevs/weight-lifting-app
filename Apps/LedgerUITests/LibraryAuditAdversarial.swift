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

    /// Fails while F12-S1-1 is open: the search field is reported "Text clipped", and it is (an edited query
    /// loses its tails from Accessibility L).
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

    static func isKnownFalsePositive(issue: String, label: String, frame: CGRect, tabBar: CGRect) -> Bool {
        switch issue {
        case "Dynamic Type font sizes are partially unsupported":
            // As Today's F09-S5-2: `Eyebrow` is 10 pt on the Caption 2 curve, flat from Extra Small to Large, so
            // it does not shrink below its default size; it grows at every size above (measured: 10 pt tall at
            // the default size, 22.3 at Accessibility L, 74 on two lines at Accessibility XXXL).
            eyebrows.contains(label)
        case "Text clipped":
            // As Today's F09-S5-4: the eyebrow's frame is its line, as tall as its size, and Archivo's ascent and
            // descent are 1.088 of it; its capitals have no tail, and the pictures at every size show it whole.
            // The search field's "Text clipped" is not excluded: it is real (F12-S1-1).
            eyebrows.contains(label)
        case "Contrast failed":
            // As Today's fourth: what rests under the floating tab bar while the page is at its top (measured:
            // every element reported lies inside the bar's frame, y 791-874, and none above it). Scrolled to
            // its end the page stands clear (`test_lastRow_scrollsClearOfTheTabBar`).
            frame.intersects(tabBar)
        default:
            false
        }
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
                    issue: issue.compactDescription, label: element.label, frame: frame, tabBar: tabBar
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
