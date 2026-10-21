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

    /// F12-S1-5 (G1 round 3, sanctioned addition): the audit's "Text clipped" on the empty search field, measured.
    /// At each size the field's picture is read row by row: the pill's two strokes are the rows inked across most of
    /// its width, and the placeholder's ink lies between them, clear of both, with no ink row cut flat against
    /// either. "Search 224 exercises" has no descender, so nothing of it can hang below its line.
    @MainActor
    func test_searchPlaceholder_isDrawnWholeInsideTheField() throws {
        for textSize in Self.sizes {
            let app = launchLibrary(textSize: textSize)
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            let shot = field.screenshot()
            attach(shot, named: "search field, \(textSize ?? "default size")")
            let ink = try XCTUnwrap(InkRows(shot.image), "the picture was not read")
            let state = "\(textSize ?? "default size"), field \(field.frame)"
            XCTAssertEqual(ink.strokes.count, 2, "\(state): the pill's two strokes: \(ink.strokes)")
            let text = try XCTUnwrap(ink.text, "\(state): no placeholder ink")
            if let top = ink.strokes.first, let bottom = ink.strokes.last {
                XCTAssertGreaterThan(text.lowerBound, top + 2, "\(state): the ink reaches the top stroke: \(text)")
                XCTAssertLessThan(text.upperBound, bottom - 2, "\(state): the ink reaches the bottom stroke: \(text)")
            }
            app.terminate()
        }
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
            // F12-S1-5 (G1 round 3): the empty search field, whose placeholder ("Search 224 exercises", no
            // descender) is drawn whole between the pill's strokes at the default size, Accessibility L and XXXL
            // (`test_searchPlaceholder_isDrawnWholeInsideTheField`; the reported frames are the field's, 350 x 44,
            // 51 and 72 pt). An edited query's tails were F12-S1-1, fixed by the field's line (`d5704eb`).
            eyebrows.contains(label) || label.hasPrefix("Search ") && label.hasSuffix(" exercises")
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

/// The rows of a picture of the search field that hold ink, against the colour of its middle-left pixel inside
/// the pill: a stroke is a run of rows faintly inked across most of the width; the placeholder is every other row
/// that holds strong ink.
private struct InkRows {
    let strokes: [Int]
    let text: ClosedRange<Int>?

    init?(_ image: UIImage) {
        guard let picture = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let width = picture.width
        let height = picture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        // The pill's ground: on the middle row, inside the round end and left of the placeholder's start.
        let ground = (width / 40, height / 2)
        func pixel(_ column: Int, _ row: Int) -> [Int] {
            (0 ..< 3).map { Int(bytes[(row * width + column) * 4 + $0]) }
        }
        let base = pixel(ground.0, ground.1)
        // The columns between the pill's round ends.
        let columns = (width / 8) ..< (width * 7 / 8)
        var strokeRows: [Int] = []
        var textRows: [Int] = []
        for row in 0 ..< height {
            // The stroke is a faint hairline (`hairlineStrong`); the placeholder's grey stands well off the ground.
            let faint = columns.count { column in zip(pixel(column, row), base).contains { abs($0 - $1) > 8 } }
            let strong = columns.count { column in zip(pixel(column, row), base).contains { abs($0 - $1) > 40 } }
            if faint > columns.count * 4 / 5 {
                strokeRows.append(row)
            } else if strong > 0 {
                textRows.append(row)
            }
        }
        // A stroke is one to a few rows thick: keep the first row of each run.
        strokes = strokeRows.enumerated()
            .filter { $0.offset == 0 || strokeRows[$0.offset - 1] != $0.element - 1 }
            .map(\.element)
        text = textRows.first.flatMap { first in textRows.last.map { first ... $0 } }
    }
}
