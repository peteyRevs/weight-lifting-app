import XCTest

/// F09 S1 adversarial round 1 (G2), for what only the running app shows: the system's tab bar as a lifter and
/// VoiceOver meet it (criteria 1, 2 and 5), in light and dark, at the largest text size, with the device turned,
/// and the debug menu after a tour of the tabs. Nightly only, as every UI test but `Smoke` is.
final class TabsAdversarial: XCTestCase {
    private static let tabs = ["Today", "Program", "Library", "History"]
    /// Sanctioned edit of F11 S14 (criterion 25): the Program tab draws the builder, which with no program (a UI
    /// test's database has none) shows its message, found by its title; the other three are found as before.
    private static let titles = ["today.title", "No program yet", "library.title", "history.title"]

    /// What each tab's title reads: its name, or for the Program tab the builder's message.
    private static func label(of tab: String) -> String {
        tab == "Program" ? "No program yet" : tab
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1"] + arguments
        app.launchArguments += ["-LEDGER_UITEST_PROGRAM", "seed"] // F08: the seed program, not onboarding
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func test_tabBar_holdsTheFourTabsInOrder_todaySelected() {
        let app = launch()
        let buttons = app.tabBars.firstMatch.buttons.allElementsBoundByIndex
        XCTAssertEqual(buttons.map(\.label), Self.tabs)
        XCTAssertEqual(buttons.map(\.isSelected), [true, false, false, false])
        let leftEdges = buttons.map(\.frame.minX)
        XCTAssertEqual(leftEdges, leftEdges.sorted(), "the order on screen is the order VoiceOver reads")
        XCTAssertTrue(buttons.allSatisfy { $0.frame.height >= 44 && $0.frame.width >= 44 }, "44 pt targets")
        XCTAssertEqual(app.staticTexts["today.title"].label, "Today")
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "a tab's root draws its own title")
    }

    @MainActor
    func test_eachTab_showsThePlaceholderThatNamesIt_andIsTheOnlyOneSelected() {
        let app = launch()
        let pairs = Array(zip(Self.tabs, Self.titles))
        for (tab, title) in pairs + pairs.reversed() {
            app.tabBars.buttons[tab].tap()
            let heading = app.staticTexts[title]
            XCTAssertTrue(heading.waitForExistence(timeout: 5), title)
            XCTAssertEqual(heading.label, Self.label(of: tab))
            let selected = app.tabBars.buttons.allElementsBoundByIndex.filter(\.isSelected).map(\.label)
            XCTAssertEqual(selected, [tab])
            let others = Self.titles.filter { $0 != title }
            let shown = others.filter { app.staticTexts[$0].exists && app.staticTexts[$0].isHittable }
            XCTAssertEqual(shown, [], "one tab's root at a time")
        }
    }

    @MainActor
    func test_debugMenu_opensFromTodaysTitleAfterATourOfTheTabs_andFromNoOtherTitle() {
        let app = launch()
        for (tab, title) in zip(Self.tabs, Self.titles).dropFirst() {
            app.tabBars.buttons[tab].tap()
            let heading = app.staticTexts[title]
            XCTAssertTrue(heading.waitForExistence(timeout: 5), title)
            heading.press(forDuration: 1)
            XCTAssertFalse(app.buttons["debug.menu.diagnostics"].waitForExistence(timeout: 2), title)
        }
        app.tabBars.buttons["Today"].tap()
        let title = app.staticTexts["today.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.press(forDuration: 1)
        XCTAssertTrue(app.buttons["debug.menu.diagnostics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["debug.menu.designGallery"].exists)
    }

    @MainActor
    func test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark() throws {
        let before = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = before }
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = appearance
            let app = launch()
            for tab in Self.tabs {
                app.tabBars.buttons[tab].tap()
                XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
                attach(app.tabBars.firstMatch.screenshot(), named: "\(tab)-\(appearance == .dark ? "dark" : "light")")
                for other in Self.tabs {
                    let share = try accentShare(of: app.tabBars.buttons[other], in: appearance)
                    if other == tab {
                        XCTAssertGreaterThan(share, 0.01, "\(tab) selected: \(other) is not in the accent")
                    } else {
                        XCTAssertLessThan(share, 0.001, "\(tab) selected: \(other) is in the accent too")
                    }
                    if appearance == .light {
                        // Criterion 5 as revised: on the light theme the tint is the deep accent. The plain
                        // accent (dark's bounds) measured 2.44:1 on the selection capsule and must be gone.
                        let plain = try accentShare(of: app.tabBars.buttons[other], in: .dark)
                        XCTAssertLessThan(plain, 0.001, "\(tab) selected, light: \(other) wears the plain accent")
                    }
                }
            }
            app.terminate()
        }
    }

    @MainActor
    func test_largestTextSize_everyTitleIsWholeAndOnScreen() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let window = app.windows.firstMatch.frame
        var heights: [CGFloat] = []
        for (tab, title) in zip(Self.tabs, Self.titles) {
            app.tabBars.buttons[tab].tap()
            let heading = app.staticTexts[title]
            XCTAssertTrue(heading.waitForExistence(timeout: 5), title)
            XCTAssertTrue(heading.isHittable, title)
            XCTAssertGreaterThanOrEqual(heading.frame.minX, window.minX, title)
            XCTAssertLessThanOrEqual(heading.frame.maxX, window.maxX, title)
            if tab != "Program" {
                // The builder's message is three words, which may wrap at this size; it is no one-word title.
                heights.append(heading.frame.height)
            }
            attach(app.screenshot(), named: "AX5-\(tab)")
        }
        let shortest = heights.min() ?? 0
        XCTAssertTrue(heights.allSatisfy { $0 < shortest * 1.5 }, "a one-word title on two lines: \(heights)")
    }

    @MainActor
    func test_deviceTurned_theAppStaysUpright() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.height, window.width, "Config/Ledger.xcconfig allows portrait alone")
        XCTAssertTrue(app.tabBars.buttons["History"].isHittable)
        XCTAssertTrue(app.staticTexts["today.title"].isHittable)
    }

    @MainActor
    func test_everyTabRoot_passesTheSystemsAccessibilityAudit() throws {
        // Sanctioned edit of the F08 port (fix round 1, F8-S2S3-4): the audit reads Today inside the seed program's
        // block, on the day `Today` and `TodayAuditAdversarial` read (Wednesday of week 5, Lower A), not after the
        // block's end, which `TodayAuditExclusions` was not measured on.
        let app = launch(["-LEDGER_UITEST_NOW", "2026-09-16T12:00:00Z"])
        var issues: [String] = []
        let tabBar = app.tabBars.firstMatch.frame
        for tab in Self.tabs {
            app.tabBars.buttons[tab].tap()
            try app.performAccessibilityAudit { issue in
                // F09 S5 round 2 (criterion 19): Today's root is now the real screen, on which the system
                // reports four issues that were measured and judged false positives (F09-S5-1 to 4). They
                // are excluded on the Today tab alone, by the issue's words and the element's label;
                // `TodayAuditExclusions` holds the element, the measurement and the reason of each.
                let isKnown = tab == "Today" && issue.element.map { element in
                    TodayAuditExclusions.isKnownFalsePositive(
                        issue: issue.compactDescription, label: element.label, frame: element.frame, tabBar: tabBar
                    )
                } ?? false
                if !isKnown {
                    let element = issue.element.map { "\($0.elementType.rawValue) \"\($0.label)\"" } ?? "no element"
                    issues.append("\(tab): \(issue.compactDescription) [\(element)]")
                }
                return true
            }
        }
        XCTAssertEqual(issues, [])
    }
}

private extension TabsAdversarial {
    /// The share of the element's pixels that are the tab bar's tint, `LedgerColor.accentText` (F09 S1 fix round 1,
    /// review S6): the accent, `#FF5B22`, in dark and the deep accent, `#B2390E`, in light, give or take the
    /// display's rendering (measured on the iPhone 17 simulator: `#FF682F` and `#A73107`).
    @MainActor
    func accentShare(of element: XCUIElement, in appearance: XCUIDevice.Appearance) throws -> Double {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context != nil
        }
        XCTAssertTrue(drawn)
        var accent = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let red = Int(bytes[pixel])
            let green = Int(bytes[pixel + 1])
            let blue = Int(bytes[pixel + 2])
            let isAccent = appearance == .dark
                ? red > 215 && (60 ... 125).contains(green) && blue < 80
                : (140 ... 200).contains(red) && (25 ... 85).contains(green) && blue < 45
            if isAccent {
                accent += 1
            }
        }
        return Double(accent) / Double(max(width * height, 1))
    }

    @MainActor
    func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
