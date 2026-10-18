import XCTest

/// F10 S7a adversarial round 1 (G2), for what only the running app shows: "End workout?" as a real sheet. Its
/// buttons at its half height at every text size, measured; a swipe down as "Keep lifting"; two quick taps
/// on "Save workout"; and the sheet mirrored. Nightly only, as every UI test but `Smoke` is.
final class WorkoutFinishAdversarial: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: The sheet at its half height, at each text size (criterion 38; the notes' product point 2)

    @MainActor
    func test_sheet_defaultSize_bothButtonsShowAtHalfHeight() {
        let found = measureSheet(category: nil)
        XCTAssertTrue(found.showsSave && found.showsDiscard, "at the default size nothing has to be scrolled to")
    }

    @MainActor
    func test_sheet_extraExtraExtraLarge_buttonsCanBeReached() {
        measureSheet(category: "UICTContentSizeCategoryXXXL")
    }

    @MainActor
    func test_sheet_accessibilityMedium_buttonsCanBeReached() {
        measureSheet(category: "UICTContentSizeCategoryAccessibilityM")
    }

    @MainActor
    func test_sheet_accessibilityExtraLarge_buttonsCanBeReached() {
        measureSheet(category: "UICTContentSizeCategoryAccessibilityXL")
    }

    @MainActor
    func test_sheet_accessibilityLargest_buttonsCanBeReached() {
        measureSheet(category: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    /// What the sheet showed when it came up, before anything was scrolled or pulled.
    private struct Found {
        var showsSave = false
        var showsDiscard = false
    }

    /// Starts the sample workout at `category`, logs a set, taps "Finish" and reads the sheet as it comes
    /// up: where its five stops stand in the window and which can be tapped. Then pulls the sheet up when a
    /// button is out of reach, and asserts that both can then be tapped. The measures are printed for the
    /// findings (`G2-SHEET`) and kept as a screenshot.
    @MainActor
    @discardableResult
    private func measureSheet(category: String?, extra: [String] = []) -> Found {
        let app = openTheSheet(category: category, extra: extra)

        let title = app.staticTexts["End workout?"].firstMatch
        let keep = app.buttons["workout.finish.keep"].firstMatch
        let summary = app.staticTexts["workout.finish.summary"].firstMatch
        let save = app.buttons["workout.finish.save"].firstMatch
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        // The sheet has come to rest when its title no longer moves.
        var top = title.frame.minY
        for _ in 0 ..< 20 {
            usleep(150_000)
            if title.frame.minY == top {
                break
            }
            top = title.frame.minY
        }
        let window = app.windows.firstMatch.frame
        let found = Found(
            showsSave: save.exists && save.isHittable,
            showsDiscard: discard.exists && discard.isHittable
        )
        let name = category?.replacingOccurrences(of: "UICTContentSizeCategory", with: "") ?? "L"
        print("G2-SHEET \(name)\(extra.isEmpty ? "" : " mirrored"): window \(Int(window.width))x\(Int(window.height));"
            + " title \(Self.place(title)); keep \(Self.place(keep)); line \(Self.place(summary));"
            + " save \(Self.place(save)); discard \(Self.place(discard))")
        attach(app.screenshot(), named: "End workout? at \(name), as it comes up")
        // Beside the title Keep lifting stands at its trailing edge; at the largest sizes it stands under it.
        if keep.frame.minY < title.frame.maxY {
            XCTAssertEqual(keep.frame.midX < window.midX, !extra.isEmpty, "Keep lifting at the trailing edge")
        }
        reachBothButtons(in: app, at: name)
        return found
    }

    /// Asserts what must hold of the sheet once it has come up, pulling it up where a button is out of
    /// reach, then discards the workout.
    @MainActor
    private func reachBothButtons(in app: XCUIApplication, at name: String) {
        let window = app.windows.firstMatch.frame
        let title = app.staticTexts["End workout?"].firstMatch
        let keep = app.buttons["workout.finish.keep"].firstMatch
        let save = app.buttons["workout.finish.save"].firstMatch
        let discard = app.buttons["workout.finish.discard"].firstMatch
        XCTAssertTrue(title.isHittable, "the title is pinned")
        XCTAssertTrue(keep.isHittable, "Keep lifting is pinned")
        // S7a-1: in the running app the sheet's cancel is 42.2 pt tall at the default size, XXXL and AX1.
        // F10 S7a fix round 1: within 0.001 pt, as the hosted checks allow (43.999999999999986 at AX M).
        XCTAssertGreaterThanOrEqual(keep.frame.height, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(keep.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(keep.frame.maxX, window.maxX)
        // A button out of reach is reached by pulling the sheet up, or by scrolling what is under its title.
        for _ in 0 ..< 3 where !(save.exists && save.isHittable && discard.exists && discard.isHittable) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertTrue(save.isHittable, "Save workout can be reached at \(name)")
        XCTAssertTrue(discard.isHittable, "Discard can be reached at \(name)")
        XCTAssertTrue(save.isEnabled)
        for button in [save, discard] {
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX)
        }
        XCTAssertTrue(keep.isHittable, "Keep lifting is still pinned after the pull")
        attach(app.screenshot(), named: "End workout? at \(name), both buttons in reach")
        discard.tap()
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func openTheSheet(category: String?, extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        let size = category.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []
        app.launchArguments = ["-LEDGER_UITEST", "1"] + size + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        startSampleWorkout(in: app)
        XCTAssertTrue(app.buttons["workout.header.minimize"].waitForExistence(timeout: 10))
        logTheFirstSet(in: app)
        app.buttons["workout.header.finish"].tap()
        return app
    }

    @MainActor
    private static func place(_ element: XCUIElement) -> String {
        guard element.exists else {
            return "none"
        }
        let frame = element.frame
        return "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
            + (element.isHittable ? "" : " (out of reach)")
    }
}

extension WorkoutFinishAdversarial {
    // MARK: The ways out (criteria 1, 8 and 13)

    /// A swipe down on the sheet is "Keep lifting": the workout stays as it was. Then two taps on "Save
    /// workout" as fast as a finger makes them: one workout is saved, the cover closes onto Today's Logged
    /// card, and no alert is left over it.
    @MainActor
    func test_swipeDown_keepsTheWorkout_thenTwoQuickTapsSaveOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["-LEDGER_UITEST", "1", "-LEDGER_UITEST_NOW", "2026-08-17T12:00:00Z"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.title"].waitForExistence(timeout: 10))
        startSampleWorkout(in: app)
        let minimize = app.buttons["workout.header.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        logTheFirstSet(in: app)

        app.buttons["workout.header.finish"].tap()
        let save = app.buttons["workout.finish.save"].firstMatch
        let title = app.staticTexts["End workout?"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: low)
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "a swipe down takes the sheet away")
        XCTAssertTrue(minimize.isHittable, "and leaves the workout up")
        XCTAssertTrue(app.buttons["Undo set 1"].exists, "with its set still logged")

        app.buttons["workout.header.finish"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.doubleTap()
        XCTAssertTrue(minimize.waitForNonExistence(timeout: 10), "the cover is down")
        // F10 S7b (edited for the audit): the receipt shows first; its "Done" takes the cover down.
        XCTAssertTrue(app.buttons["workout.receipt.done"].waitForExistence(timeout: 10), "the receipt")
        app.buttons["workout.receipt.done"].tap()
        XCTAssertTrue(app.buttons["View session"].waitForExistence(timeout: 5), "Today shows the session as logged")
        XCTAssertEqual(app.staticTexts.matching(identifier: "LOGGED · WEEK 1").count, 1)
        XCTAssertFalse(app.buttons["Resume workout"].exists, "nothing is live")
        XCTAssertFalse(app.alerts.firstMatch.exists, "no alert is left over Today")
        XCTAssertFalse(app.staticTexts["End workout?"].exists)
        attach(app.screenshot(), named: "Today after two quick taps on Save workout")
    }

    /// Right to left the sheet is mirrored: "Keep lifting" stands at the left, and both buttons answer.
    @MainActor
    func test_rightToLeft_theSheetIsMirrored() {
        measureSheet(category: nil, extra: ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
    }
}

extension WorkoutFinishAdversarial {
    // MARK: Helpers

    @MainActor
    private func logTheFirstSet(in app: XCUIApplication) {
        let log = app.buttons["Log set 1"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        XCTAssertTrue(app.buttons["Undo set 1"].waitForExistence(timeout: 5))
    }

    /// Opens the Debug menu from Today's title and taps "Start sample workout".
    @MainActor
    private func startSampleWorkout(in app: XCUIApplication) {
        app.staticTexts["today.title"].press(forDuration: 1)
        let row = app.buttons["debug.menu.startSampleWorkout"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    @MainActor
    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
